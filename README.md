# node-vps-kit

Install and update Node apps on an **Ubuntu** VPS (systemd + nginx). PowerShell 7.

This repo is the operator tool for a family of apps. Profiles live here
(`apps/<id>.psd1`); the kit is allowed to know those apps. Operators never clone
an app git tree onto the server.

The kit itself is **one copy** on the box (`/usr/local/lib/node-vps-kit`). It
refreshes from GitHub at the start of each command when possible, and keeps
working offline from that last copy if GitHub is unreachable. App instances are
the opposite: many named installs, each with its own code tree so they can run
different versions.

## Requirements

- Ubuntu with root (`sudo`)
- PowerShell 7 via snap: `sudo snap install powershell --classic`
- Node.js ≥ the app’s `NodeMajor` (**system-wide**, not only nvm)
- `tar`, `systemctl`
- `nginx` unless `-SkipNginx`

Optional: `sudo snap refresh --hold powershell` after a known-good revision.

## Install an app

```bash
sudo snap install powershell --classic

curl -fsSL https://raw.githubusercontent.com/r-a-i-t-h/node-vps-kit/main/install.ps1 \
  | sudo pwsh -File - \
      -App proseden \
      -Name www \
      -ServerName www.proseden.co.uk \
      -Port 3336
```

If piping arguments is awkward on your host:

```bash
curl -fsSL https://raw.githubusercontent.com/r-a-i-t-h/node-vps-kit/main/install.ps1 \
  -o /tmp/nvk-install.ps1
sudo pwsh -File /tmp/nvk-install.ps1 \
  -App proseden -Name www -ServerName www.proseden.co.uk -Port 3336
```

That command:

1. Fetches this kit (when piped) or uses a local checkout / `/usr/local/lib/node-vps-kit`.
2. Loads `apps/proseden.psd1`.
3. Downloads the app’s GitHub Release (`.tar.gz` or `.zip`), with a shared cache of the last 3 fetched tags per app under `/var/cache/node-vps-kit/`.
4. Unpacks under `/opt/<app>/<name>/releases/<tag>` and points `current` at it.
5. Creates empty `data/` (the app may seed on first boot), writes `env`, systemd unit, nginx.
6. Installs the kit to `/usr/local/lib/node-vps-kit` and wrappers:
   - `/usr/local/sbin/<app>-install`
   - `/usr/local/sbin/<app>-update`
   - `/usr/local/sbin/nvk-startup`

Wrappers use `#!/snap/bin/pwsh`.

### Subdomain vs path mount

| Mode | Flags |
|---|---|
| Dedicated hostname | `-ServerName HOST` (app at `/`) |
| Path on existing site | `-NginxSite FILE -BasePath PATH` |

Multiple instances: different `-Name`, `-Port`, and hostname or base path. Each keeps its own app copy and `data/`.

## Update one instance

```bash
sudo proseden-update -Name test
sudo proseden-update -Name www -Version v0.2.0
```

The updater backs up `data/` to a zip, swaps the app tree, runs optional
`deploy/post-update.sh` from the release (as the app user), and restarts systemd.
Instance `releases/` keeps the current and previous unpacked trees.

If GitHub is down and that tag is among the last 3 cached downloads, the update
still runs. Offline `-Version latest` uses the most recently fetched cached tag
(and says so).

## Boot units (startup)

Install already `enable --now`s a systemd unit named `<app>-<instance>` so the
process starts on VPS boot.

```bash
sudo nvk-startup                          # list
sudo nvk-startup -Remove -App proseden -Name www
sudo nvk-startup -Add -App proseden -Name www
```

`-Remove` only drops the unit (stop, disable, delete the file). Code, data, and
nginx stay. `-Add` writes the unit from the template again and `enable --now`.

## Layout on disk

```
/opt/<app>/<name>/
  current -> releases/vX.Y.Z
  releases/vX.Y.Z/     # unpacked archive
  data/                # live data — updates never replace this
  backup/              # timestamped data zips
  env                  # PORT, <PREFIX>_DATA, … — survives updates

/usr/local/lib/node-vps-kit/   # this kit (one copy)
/usr/local/sbin/<app>-install
/usr/local/sbin/<app>-update
/usr/local/sbin/nvk-startup

/var/cache/node-vps-kit/<app>/<tag>/   # last 3 downloaded archives per app
```

## App author: register a profile

Add `apps/<id>.psd1` in this repo:

```powershell
@{
    AppId           = 'myapp'
    Repo            = 'owner/myapp'
    Tarball         = 'myapp.tar.gz'   # or .zip
    Prefix          = '/opt/myapp'
    User            = 'myapp'
    NodeMajor       = 20
    ArchiveRoot     = 'myapp'
    ServerEntry     = 'dist/server.js'
    EnvPrefix       = 'MYAPP'
    HealthPath      = 'health'
    HasSeed         = $true
    HasBasePath     = $true
    NginxExtra      = ''               # or live-events for SSE locations
    EnvExtra        = @('MYAPP_SECURE_COOKIES=1')
    PostInstallNote = 'Optional note printed after install'
}
```

### Release archive contract

Ship a `.tar.gz` or `.zip` whose top-level directory is `ArchiveRoot`, containing:

- `VERSION`
- `ServerEntry` (default `dist/server.js`)
- optional `seed/` (copied by the app on first boot when data is empty)
- optional `deploy/post-update.sh` (migrations; runs as the app user before restart)

Do **not** put install/update scripts in the app release; this kit owns them.

GitHub’s automatic “Source code (zip)” is the git tree, not this artifact. Attach
a packed release asset in CI.

### Env conventions

On first install the kit writes:

- `NODE_ENV=production`
- `PORT=…`
- `${EnvPrefix}_DATA=…/data`
- `${EnvPrefix}_SEED=…/current/seed` if `HasSeed`
- `${EnvPrefix}_BASE_PATH=…` if `HasBasePath`
- plus `EnvExtra`

Updates never rewrite `env` except refreshing the `_SEED` path to the new tree.

## Local development of the kit

```bash
sudo NVK_ROOT=/path/to/node-vps-kit \
  pwsh -File /path/to/node-vps-kit/install.ps1 \
    -App proseden -Name www -ServerName www.example.com -Port 3336
```

`NVK_ROOT` skips GitHub self-update so you run the checkout. Running
`install.ps1` / `update.ps1` / `startup.ps1` from a git checkout (not from
`/usr/local/lib/node-vps-kit`) also skips the refresh.

`KIT_REPO` / `KIT_REF` (default `r-a-i-t-h/node-vps-kit` / `main`) control which
kit revision is fetched when the installed copy refreshes or when `install.ps1`
is piped.

Private GitHub repos: export `GITHUB_TOKEN` with read access.

If a self-update installs a broken kit, recover with another `curl | sudo pwsh`
of `install.ps1` from GitHub (there is no kit version history).
