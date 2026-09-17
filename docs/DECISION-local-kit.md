# Decision: kit as a first-class local tool

Status: **accepted** (direction for later kit CLI changes; not fully implemented).
The kit on disk is now PowerShell 7 (`install.ps1`, `update.ps1`, `startup.ps1`, `Nvk.psm1`).
Best-effort self-update on each command is implemented. Explicit `nvk self-update` / POSIX bootstrap are still out of scope.

Context: extracted from Proseden deploy scripts; rewritten in pwsh in this repo.

## Problem

The first kit cut treats installer presence as a **side effect** of installing an app:

1. `curl …/install.sh | bash -- --app proseden …` installs both the app and `/usr/local/lib/node-vps-kit`.
2. Later, `proseden-install` / `proseden-update` run the **local** copy.
3. Local `*-install` does **not** fetch the latest kit first, so it can be silently stale (missing new `apps/*.conf`, missing install/nginx fixes).
4. App-update refreshes the kit mainly at the **end** of a run, so *this* run may still have used an old kit.

That is hard to reason about: the tool feels local and trustworthy, but only curl is reliably current.

## Decision

**Arrangement 1 — local install + update scripts; installer freshness is an explicit maintainer concern.**

Rejected alternative: “install only via curl; keep only a local update script.” That makes install always fresh but splits the product (install is ephemeral HTTP, update is local) and still leaves update staleness unless update always pulls the kit anyway.

### Operator model

1. **Install the installer** (via curl) onto the VPS → `/usr/local/lib/node-vps-kit` plus PATH helpers.
2. **Use local** `*-install` / `*-update` (and a kit self-update command) for day-to-day work, including when a known on-disk kit is preferred.
3. **Update the installer explicitly** when it might be out of date (new app registered in the kit, kit bugfix, long idle).
4. **Optionally / preferably:** refresh the kit at the **start** of every app-update so routine app bumps do not leave the host on an ancient kit by accident.

Mental model: *you own the tool; the tool installs apps.* App releases (`dist/`, `seed/`, `deploy/post-update.sh`) stay in each app’s GitHub Releases. The kit owns install/update logic, `apps/*.conf`, and systemd/nginx templates.

### What stays true

| Piece | Owner |
|---|---|
| `install` / `update` / app profiles / unit + nginx templates | **kit** |
| Release tarball + optional `deploy/post-update.sh` / migrations | **each app** |
| Instance `data/` + `env` | **instance** (never re-seeded by update) |
| Multi-instance, subdomain vs path mount, seed-on-first-boot via env | **unchanged concepts** |

### What we will change (implementation plan)

Not done yet in the current tree; this is the backlog when resuming in this repo.

1. **First-class kit bootstrap**
   - Dedicated entrypoint, e.g. `bootstrap.sh` or `install-kit.sh`, curl|bashable.
   - Installs/refreshes `/usr/local/lib/node-vps-kit`.
   - Installs PATH commands such as `node-vps-kit` / `nvk` with subcommands, or at least `node-vps-kit-update` (name TBD).

2. **First-class kit self-update**
   - Explicit: `node-vps-kit-update` (or `nvk self-update`) fetches `KIT_REPO` @ `KIT_REF` and replaces the local tree + wrappers.
   - Docs: run this before adding a **new** app, or if the kit has not been refreshed for a while.

3. **App install**
   - Prefer: kit already present → `proseden-install …` (wrapper).
   - Convenience: curl of app `install.sh` may still ensure the kit exists (bootstrap if missing), but must not be the only documented story.
   - Local install should not pretend to be “always latest”; docs state maintainer responsibility (and/or a soft warning if kit is old / cannot check upstream).

4. **App update**
   - Refresh kit from GitHub at the **start** of the run (use that tree for this update), then proceed with app tarball / backup / post-update / restart.
   - Still rewrite sbin wrappers from the refreshed kit.
   - Keeps “I updated Proseden” aligned with “this run used a current kit.”

5. **Wrappers**
   - Per-app: `/usr/local/sbin/<app>-install`, `<app>-update` → kit with `--app <id>`.
   - Created/refreshed when the kit is installed/updated and when that app is first installed.

6. **Proseden cutover (separate repo, after kit is published)**
   - Do **not** merge Proseden thin shims until this kit is on GitHub and the operator contract above is implemented (or at least bootstrap + self-update + start-of-update refresh).
   - Prefer a transitional Proseden `deploy/update.sh` that does not replace a working sbin updater with a shim that depends on an unpublished kit.
   - Point Proseden `DEPLOY.md` / README at: install kit → `proseden-install` / `proseden-update`.

### Explicitly out of scope (still)

- npm package for VPS bootstrap (curl|bash stays the distribution).
- Caddy (nginx + systemd remain the default).
- Changing Proseden in-app seed-on-missing-meta behaviour.

## Happy path (target docs)

```bash
# 1. Install / refresh the installer
curl -fsSL https://raw.githubusercontent.com/r-a-i-t-h/node-vps-kit/main/bootstrap.sh \
  | sudo bash -s --

# 2. Install an app instance (local tool)
sudo proseden-install --name www --server-name www.example.com --port 3336

# 3. Later: update that instance (kit refreshes at start of this run)
sudo proseden-update --name www

# 4. Before a new app, or after a long gap: update the installer explicitly
sudo node-vps-kit-update
sudo otherapp-install --name www …
```

Exact script/command names can be adjusted during implementation; the contract above should not.

## Why not “install only via curl”

- Multi-app kit wants one local product on the box.
- Forbidding local install only papers over staleness for one verb; update still needs a freshness story.
- Once update always pulls the kit, “no local install” is mostly ritual.
- Offline / repeatable ops favour a known local tree plus an explicit refresh step.

## Resume checklist

When continuing work with this repo open:

- [ ] Add bootstrap / self-update entrypoints and PATH helpers.
- [ ] Move kit GitHub refresh to the **start** of app-update.
- [ ] Clarify README operator contract (install kit → install apps → update kit when stale).
- [ ] Publish repo `r-a-i-t-h/node-vps-kit` on GitHub.
- [ ] Only then finish Proseden migration (docs + safe transitional update shim).
