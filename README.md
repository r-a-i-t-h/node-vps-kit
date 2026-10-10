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
- `/usr/local/sbin/nvk-startup` — add or remove the boot unit
- `/usr/local/sbin/nvk-service` — start, stop, or restart the running service
- `/usr/local/sbin/nvk-info` — kit version, installable apps, host summary, installed instances
- `/usr/local/sbin/nvk-nginx` — serve a directory of HTML files (a new hostname, or a path on an existing site)
- `/usr/local/sbin/nvk-app-install` / `nvk-app-update` — install or update an app instance
- `/usr/local/sbin/nvk-app-uninstall` — delete an app instance (nginx, systemd, and its directory)

Wrappers use `#!/snap/bin/pwsh`.

Those commands are wrappers, not renamed copies. The kit files stay under `/usr/local/lib/node-vps-kit` with their repo names. Each wrapper is a short `pwsh` script that runs the matching file and forwards its arguments:

| Command | Runs |
|---|---|
| `nvk-update` | `bootstrap.ps1` |
| `nvk-startup` | `startup.ps1` |
| `nvk-service` | `service.ps1` |
| `nvk-info` | `info.ps1` |
| `nvk-nginx` | `nginx.ps1` |
| `nvk-app-install` | `install.ps1` |
| `nvk-app-uninstall` | `uninstall.ps1` |
| `nvk-app-update` | `update.ps1` |

## Install an app

The kit must already be on the box.

```bash
sudo nvk-app-install -App proseden -Name www -ServerName www.proseden.co.uk -Port 3336
sudo nvk-app-install -App tessera -Name www -ServerName www.example.com -Port 7356
```

Omit flags on a terminal and the command offers a numbered menu (`1` / `a` select the first item), including which app when `-App` is omitted. You can also type a value. Non-interactive runs still need the flags.

That command:

1. Loads `apps/<id>.psd1` from the local kit (after `-App` or the menu).
2. Downloads the app’s GitHub Release (`.tar.gz` or `.zip`), with a shared cache of the last 3 fetched tags per app under `/var/cache/node-vps-kit/`.
3. Unpacks under `/opt/<app>/<name>/releases/<tag>` and points `current` at it.
4. Creates empty `data/` (the app may seed on first boot), writes `env`, systemd unit, nginx.

The nginx site proxies every path to Node, including `/`, and sends `Cache-Control: private, max-age=0, must-revalidate`. Browsers and shared caches must ask again before reusing a response. Nginx does not store those responses and does not invent an ETag; it forwards one when the app sends it. That file is written at install. App update does not rewrite it.

It does **not** refresh the kit. If the app profile is missing, update the kit
first (`sudo nvk-update`).

### Subdomain vs path mount

| Mode | Flags | Apps |
|---|---|---|
| Dedicated hostname | `-ServerName HOST` (app at `/`) | every profile |
| Path on existing site | `-NginxSite FILE -BasePath PATH` | profiles with `HasBasePath` |

Tessera’s profile sets `HasBasePath` to `$false`, so it installs on a dedicated hostname. Proseden accepts either mode.

Multiple instances: different `-Name`, `-Port`, and hostname or base path. Each keeps its own app copy and `data/`.

## Static websites

`nvk-nginx` serves a directory of HTML files. It does not install a Node app and it does not proxy. Use it for a published site, such as a Tessera export.

```bash
sudo nvk-nginx -ServerName books.example.com -Root /var/www/books
sudo nvk-nginx -NginxSite /etc/nginx/sites-available/www.example.com -BasePath books -Root /var/www/books
sudo nvk-nginx
```

Omit flags on a terminal and the command asks. The usual case is a new hostname (a subdomain). The other case adds a URL prefix on a site that already exists.

A new hostname writes `/etc/nginx/sites-available/<server_name>` and a symlink in `sites-enabled`. The file listens on 80 and on 443. Port 80 includes `/etc/nginx/snippets/nvk-https-redirect.conf`, which redirects to HTTPS. The certificate is the one already in the http context (`conf.d`), or lines certbot adds on that server — the same rule as an app site. `nginx -t` fails until a certificate exists.

A subdirectory writes a snippet under `/etc/nginx/snippets/` and includes it in the existing site’s TLS server. The files stay in `-Root`. The URL is `/<base path>/`.

Both send `Cache-Control: no-cache`. A browser may store a file, and it checks with nginx before using that copy, so a changed file is served on the next visit. An unchanged file is answered with 304.

`-Root` must already exist. This command does not publish files.

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

## Uninstall one instance

```bash
sudo nvk-app-uninstall -App proseden -Name www
sudo nvk-app-uninstall -App proseden -Name www -Yes
```

On a terminal, `sudo nvk-app-uninstall` with no `-App` / `-Name` lists apps and installed instances. It then prints what it will delete and asks you to type the instance name. Non-interactive runs need `-App`, `-Name`, and `-Yes`.

The service must already be stopped (`sudo nvk-service -Stop -App proseden -Name www`). Uninstall refuses while that service is running, starting, or stopping, and it does not stop the service itself.

This deletes that instance's nginx site or path-mount snippet (and the `include` line in an existing site), its systemd unit, and `/opt/<app>/<name>/` — code, `data/`, `backup/`, and `env`. The system user stays. Let's Encrypt certificates under `/etc/letsencrypt` stay. Paths in `env` that point outside the instance directory are left in place and listed.

The instance directory is read from the systemd unit when that unit is still installed. Pass `-Prefix` when the unit is already gone and install used a prefix other than the app profile default.

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

## Kit and host info

```bash
sudo nvk-info
```

Prints the kit version and commit date, the apps this kit can install, a short host summary
(CPU, memory, disk, load, uptime, Node, and PowerShell), then the installed
instances. That last section is `nvk-service -List` (the switch is `-List`).

The version is a short git commit, then `repo@ref`. `committed` is that
commit’s date in UTC — the stand-in for a kit version number. Install and
update record both on the box. A checkout (`pwsh -File info.ps1`, or
`NVK_ROOT`) shows that checkout’s commit and its date. If the commit cannot
be read, the version line is just `repo@ref`. The command does not change the
kit or any instance, and it does not need root when `nvk-info` is already on
`PATH`.

## Start and stop a server

`nvk-service` starts, stops, and restarts the systemd service for an installed
instance. The service name is `<app>-<name>` (the `www` instance of `proseden`
is `proseden-www`). The unit file and its boot setting stay in place, as do
code, `data/`, `env`, and nginx. An enabled service that you have stopped
comes back on the next boot.

```bash
sudo nvk-service
sudo nvk-service -Stop -App proseden -Name www
sudo nvk-service -Start -App proseden -Name www
sudo nvk-service -Restart -App proseden -Name www
sudo nvk-service -List
```

On a terminal, `sudo nvk-service` prints each service’s state, then a numbered
menu for start, stop, or restart, then the instance (`1` / `a` selects the
first item). `-List` prints the table and exits. Non-interactive runs need the
action and `-App` / `-Name`.

Logs: `sudo journalctl -u proseden-www -f`

Dropping the unit so it stays down across reboot is `nvk-startup -Remove`, in
the next section.

## Boot units (startup)

Install already `enable --now`s a systemd unit named `<app>-<instance>` so the
process starts on VPS boot.

```bash
sudo nvk-startup
sudo nvk-startup -Remove -App proseden -Name www
sudo nvk-startup -Add -App proseden -Name www
sudo nvk-startup -List
```

On a terminal, `sudo nvk-startup` prints each instance, then a numbered menu
for add or remove, then the instance (`1` / `a` selects the first item).
`-List` prints the table and exits. Non-interactive runs need the action and
`-App` / `-Name`.

`-Remove` drops the unit (stop, disable, delete the file). Code, data, and
nginx stay. `-Add` writes the unit from the template again and `enable --now`.
To delete the instance directory and nginx as well, use `nvk-app-uninstall`.

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
/usr/local/sbin/nvk-service
/usr/local/sbin/nvk-info
/usr/local/sbin/nvk-nginx
/usr/local/sbin/nvk-app-install
/usr/local/sbin/nvk-app-uninstall
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
    HasBasePath     = $true            # $false: dedicated hostname only
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
