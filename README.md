# node-vps-kit

Install and update Node apps on an **Ubuntu** VPS (systemd + nginx). PowerShell 7.

This repo is the operator tool for a family of apps. Profiles live here
(`apps/<id>.psd1`); the kit is allowed to know those apps. Operators never clone
an app git tree onto the server.

The kit itself is **one copy** on the box (`/usr/local/lib/node-vps-kit`).
Install it once, then use it to install apps. It stays at that revision until
you explicitly run `nvk-update`. App instances are the opposite: many named
installs, each with its own code tree so they can run different versions.

## Requirements

- Ubuntu with root (`sudo`)
- PowerShell 7 via snap: `sudo snap install powershell --classic`
- Node.js ≥ the app’s `NodeMajor` (**system-wide**, not only nvm)
- `tar`, `systemctl`
- `nginx` unless `-SkipNginx`

**Ubuntu only.** macOS is not supported. Test on Ubuntu — a Lima VM, another
Linux VM, or the VPS — using `NVK_ROOT` if you are editing this repo. See
[docs/DECISION-macos.md](docs/DECISION-macos.md) and the beginner walkthrough
[docs/LOCAL-TESTING.md](docs/LOCAL-TESTING.md).

Optional: `sudo snap refresh --hold powershell` after a known-good revision.

## Install the kit

```bash
sudo snap install powershell --classic

curl -fsSL https://raw.githubusercontent.com/r-a-i-t-h/node-vps-kit/main/bootstrap.ps1 |
  sudo pwsh -File -
```

If piping is awkward on your host:

```bash
curl -fsSL https://raw.githubusercontent.com/r-a-i-t-h/node-vps-kit/main/bootstrap.ps1 \
  -o /tmp/nvk-bootstrap.ps1
sudo pwsh -File /tmp/nvk-bootstrap.ps1
```

That writes `/usr/local/lib/node-vps-kit` and PATH wrappers:

- `/usr/local/sbin/nvk-update` — refresh this kit (and app profiles)
- `/usr/local/sbin/nvk-startup`
- `/usr/local/sbin/nvk-app-install` / `nvk-app-update` — install or update an app instance

Wrappers use `#!/snap/bin/pwsh`.

## Install an app

The kit must already be on the box.

```bash
sudo nvk-app-install -App proseden -Name www -ServerName www.proseden.co.uk -Port 3336
```

Omit flags on a terminal and the command offers a numbered menu (`1` / `a` select the first item), including which app when `-App` is omitted. You can also type a value. Non-interactive runs still need the flags.

That command:

1. Loads `apps/<id>.psd1` from the local kit (after `-App` or the menu).
2. Downloads the app’s GitHub Release (`.tar.gz` or `.zip`), with a shared cache of the last 3 fetched tags per app under `/var/cache/node-vps-kit/`.
3. Unpacks under `/opt/<app>/<name>/releases/<tag>` and points `current` at it.
4. Creates empty `data/` (the app may seed on first boot), writes `env`, systemd unit, nginx.

It does **not** refresh the kit. If the app profile is missing, update the kit
first (`sudo nvk-update`).

### Subdomain vs path mount

| Mode | Flags |
|---|---|
| Dedicated hostname | `-ServerName HOST` (app at `/`) |
| Path on existing site | `-NginxSite FILE -BasePath PATH` |

Multiple instances: different `-Name`, `-Port`, and hostname or base path. Each keeps its own app copy and `data/`.

## Update one instance

```bash
sudo nvk-app-update -App proseden -Name test
sudo nvk-app-update -App proseden -Name www -Version v0.2.0
```

On a terminal, `sudo nvk-app-update` with no `-App` / `-Name` lists apps and installed instances.

The updater backs up `data/` to a zip, swaps the app tree, runs optional
`deploy/post-update.sh` from the release (as the app user), and restarts systemd.
Instance `releases/` keeps the current and previous unpacked trees.

If GitHub is down and that tag is among the last 3 cached downloads, the update
still runs. Offline `-Version latest` uses the most recently fetched cached tag
(and says so).

App update does **not** refresh the kit.

## Update the kit

```bash
sudo nvk-update
```

Fetches `KIT_REPO` @ `KIT_REF` (default `r-a-i-t-h/node-vps-kit` / `main`),
replaces `/usr/local/lib/node-vps-kit`, and rewrites wrappers. New `apps/*.psd1`
profiles show up here — run this before installing an app the local kit does
not yet know.

Private GitHub repos: export `GITHUB_TOKEN` with read access.

If a kit update installs a broken copy, recover with another `curl | sudo pwsh`
of `bootstrap.ps1` from GitHub (there is no kit version history).

## Boot units (startup)

Install already `enable --now`s a systemd unit named `<app>-<instance>` so the
process starts on VPS boot.

```bash
sudo nvk-startup                          # list
sudo nvk-startup -Remove -App proseden -Name www
sudo nvk-startup -Add -App proseden -Name www
sudo nvk-startup -Remove                  # pick the instance from a menu
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
/usr/local/sbin/nvk-update
/usr/local/sbin/nvk-startup
/usr/local/sbin/nvk-app-install
/usr/local/sbin/nvk-app-update

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

Operators pick up a new profile with `sudo nvk-update`.

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

Do this on **Ubuntu** (the VPS or a VM). The host you edit on can be a Mac;
the kit still has to run on Ubuntu.

### Lima on a Mac

Step-by-step (cloud images, cloud-init, SSH, port forwards, mkcert vs
certbot): [docs/LOCAL-TESTING.md](docs/LOCAL-TESTING.md).

Short version: download the Ubuntu **26.04** cloud `.img` (not the live-server
ISO), then:

```bash
# default path: ~/Downloads/ubuntu-26.04-server-cloudimg-arm64.img  (Apple Silicon)
./scripts/lima-up.sh
limactl shell nvk
```

### NVK_ROOT

Install a checkout onto Ubuntu (does not fetch GitHub):

```bash
sudo NVK_ROOT=/path/to/node-vps-kit \
  pwsh -File /path/to/node-vps-kit/bootstrap.ps1
```

Run app install/update from that checkout without copying it:

```bash
sudo NVK_ROOT=/path/to/node-vps-kit \
  pwsh -File /path/to/node-vps-kit/install.ps1 \
    -App proseden -Name www -ServerName www.example.com -Port 3336
```

`KIT_REPO` / `KIT_REF` control which revision `nvk-update` and a piped
`bootstrap.ps1` fetch.
