# Decision: kit as a first-class local tool

Status: **accepted and implemented**.
The kit on disk is PowerShell 7 (`bootstrap.ps1`, `install.ps1`, `update.ps1`, `startup.ps1`, `Nvk.psm1`).
Kit freshness is an **explicit** operator action (`nvk-update` / piped `bootstrap.ps1`). App install and app update do not refresh the kit.

Context: extracted from Proseden deploy scripts; rewritten in pwsh in this repo.

## Problem

An earlier kit cut treated installer presence as a **side effect** of installing an app:

1. `curl …/install.ps1 | pwsh -- -App proseden …` installed both the app and `/usr/local/lib/node-vps-kit`.
2. Later, `proseden-install` / `proseden-update` ran the **local** copy.
3. Best-effort self-update on every command made the local tool feel current, but hid when GitHub was skipped and mixed “install the tool” with “install an app”.

That is hard to reason about: the tool is a product, not a by-product of the first app.

## Decision

**Arrangement 1 — local install + update scripts; installer freshness is an explicit maintainer concern.**

Rejected alternative: “install only via curl; keep only a local update script.” That makes install always fresh but splits the product (install is ephemeral HTTP, update is local) and still leaves update staleness unless update always pulls the kit anyway.

Rejected later alternative: refresh the kit automatically at the start of every app-update. That still couples “bump Proseden” to “bump the installer.” Operators who want a known on-disk kit would have to fight the tool. New app profiles are fetched when the kit is updated on purpose.

### Operator model

1. **Install the installer** (via curl) onto the VPS → `/usr/local/lib/node-vps-kit` plus PATH helpers.
2. **Use local** `*-install` / `*-update` (and `nvk-update`) for day-to-day work, including when a known on-disk kit is preferred.
3. **Update the installer explicitly** when it might be out of date (new app registered in the kit, kit bugfix, long idle). That fetch also replaces `apps/*.psd1` and rewrites per-app wrappers.

Mental model: *you own the tool; the tool installs apps.* App releases (`dist/`, `seed/`, `deploy/post-update.sh`) stay in each app’s GitHub Releases. The kit owns install/update logic, `apps/*.psd1`, and systemd/nginx templates.

### What stays true

| Piece | Owner |
|---|---|
| `install` / `update` / app profiles / unit + nginx templates | **kit** |
| Release tarball + optional `deploy/post-update.sh` / migrations | **each app** |
| Instance `data/` + `env` | **instance** (never re-seeded by update) |
| Multi-instance, subdomain vs path mount, seed-on-first-boot via env | **unchanged concepts** |

### What we changed

1. **First-class kit bootstrap**
   - `bootstrap.ps1`, curl|pwshable.
   - Installs/refreshes `/usr/local/lib/node-vps-kit`.
   - Installs PATH commands: `nvk-update`, `nvk-startup`, `<app>-install`, `<app>-update`.

2. **First-class kit self-update**
   - Explicit: `nvk-update` fetches `KIT_REPO` @ `KIT_REF` and replaces the local tree + wrappers (including new app profiles).
   - Docs: run this before adding a **new** app, or if the kit has not been refreshed for a while.

3. **App install**
   - Kit already present → `proseden-install …` (wrapper).
   - Local install does not fetch the kit. Missing profile → error that points at `nvk-update`.
   - Piped `install.ps1` is not a kit installer.

4. **App update**
   - Uses the on-disk kit only. Does not pull GitHub for the kit.
   - App tarball / backup / post-update / restart unchanged.

5. **Wrappers**
   - Per-app: `/usr/local/sbin/<app>-install`, `<app>-update` → kit with `-App <id>`.
   - Created/refreshed when the kit is installed or `nvk-update`d.

6. **Proseden cutover (separate repo, after kit is published)**
   - Do **not** merge Proseden thin shims until this kit is on GitHub and the operator contract above is implemented.
   - Prefer a transitional Proseden `deploy/update.sh` that does not replace a working sbin updater with a shim that depends on an unpublished kit.
   - Point Proseden `DEPLOY.md` / README at: install kit → `proseden-install` / `proseden-update`.

### Explicitly out of scope (still)

- npm package for VPS bootstrap (curl|pwsh stays the distribution).
- Caddy (nginx + systemd remain the default).
- Changing Proseden in-app seed-on-missing-meta behaviour.

## Happy path (docs)

```bash
# 1. Install / refresh the installer
curl -fsSL https://raw.githubusercontent.com/r-a-i-t-h/node-vps-kit/main/bootstrap.ps1 \
  | sudo pwsh -File -

# 2. Install an app instance (local tool)
sudo proseden-install -Name www -ServerName www.example.com -Port 3336

# 3. Later: update that instance (still the on-disk kit)
sudo proseden-update -Name www

# 4. Before a new app, or after a long gap: update the installer explicitly
sudo nvk-update
sudo otherapp-install -Name www …
```

## Why not “install only via curl”

- Multi-app kit wants one local product on the box.
- Forbidding local install only papers over staleness for one verb; update still needs a freshness story.
- Once update always pulls the kit, “no local install” is mostly ritual.
- Offline / repeatable ops favour a known local tree plus an explicit refresh step.

## Resume checklist

When continuing work with this repo open:

- [x] Add bootstrap / self-update entrypoints and PATH helpers.
- [x] Do **not** auto-refresh the kit on app-install or app-update.
- [x] Clarify README operator contract (install kit → install apps → update kit when stale).
- [ ] Publish repo `r-a-i-t-h/node-vps-kit` on GitHub.
- [ ] Only then finish Proseden migration (docs + safe transitional update shim).
