# Decision: no macOS fork

Status: **accepted**.
The kit stays Ubuntu-only. There is no Darwin adapter layer in `Nvk.psm1`.

Context: considered installing and updating apps on a macOS laptop as well as on an Ubuntu VPS. See also [DECISION-local-kit.md](DECISION-local-kit.md).

## Problem

The kit is meant for a VPS (systemd, Debian nginx, snap PowerShell, `useradd`). Running it on a Mac laptop is tempting for two reasons:

1. **Test double** — exercise install/update without SSHing to the box.
2. **Native Mac product** — `/opt` app instances on the laptop as a first-class target.

Those are different jobs. Mixing them would add platform branches to every later change of install, update, nginx, and startup.

## Decision

**Do not fork.** Keep the operator contract Ubuntu-only. Test the kit on Ubuntu (VM, container with systemd, or the VPS), including from a Mac checkout via `NVK_ROOT`.

Rejected: native macOS support (Homebrew nginx, current user, hand-start Node, listen 8080). That is a second product, not “the VPS kit on a laptop.” It doubles the matrix forever.

Rejected: using the Mac as a VPS test double. A realistic Mac port would skip or change the failures that matter on a box (systemd starting Node as the nologin user, Debian nginx on :80, `chown user:user`, snap `pwsh` shebangs). A green laptop run would not prove the VPS path. Unpack, cache, `env`, and `post-update.sh` can already be exercised on Ubuntu with `NVK_ROOT`.

Rejected shape (so this is not re-litigated as “just a few ifs”): a cached host object for paths/ports/shebang; `nginx -V` for Homebrew `servers/` vs `/etc/nginx/sites-available`; adapters that skip `useradd`/`systemctl`, `chown` to `SUDO_USER:staff`, reload nginx only if already running, and never start Node. Navigable, not tiny. New failure modes (brew vs `sudo nginx`, Node vanishing under `sudo`) would sit in the same functions used on a VPS.

## How to test

Run the real kit on Ubuntu. From a Mac, follow [LOCAL-TESTING.md](LOCAL-TESTING.md)
(`./scripts/lima-up.sh` and a local 26.04 cloud `.img`). Copy or mount the tree
onto any Ubuntu host and use the existing local-dev hooks:

```bash
sudo NVK_ROOT=/path/to/node-vps-kit \
  pwsh -File /path/to/node-vps-kit/bootstrap.ps1

sudo NVK_ROOT=/path/to/node-vps-kit \
  pwsh -File /path/to/node-vps-kit/install.ps1 \
    -App proseden -Name www -ServerName www.example.com -Port 3336
```

That hits systemd, Debian nginx, `useradd`, and snap pwsh — the actual operator contract.

## What stays true

- One on-disk kit at `/usr/local/lib/node-vps-kit`.
- App instances under `/opt/<app>/<name>/`.
- `NVK_ROOT` still means “use this checkout,” not “this host is macOS.”
