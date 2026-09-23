# Local testing (Lima on a Mac)

This kit installs and updates Node apps on **Ubuntu** (systemd, Debian nginx,
snap PowerShell, a dedicated system user). It does **not** run on macOS. A
Mac-native port would skip or change the parts that actually break on a VPS, so
a green laptop run would not prove the production path. See
[DECISION-macos.md](DECISION-macos.md).

The supported way to test from a Mac is: keep editing the kit on the Mac, and
run the kit **inside a real Ubuntu virtual machine**. This repo includes a
small Lima helper for that.

You do not need to know Lima, cloud images, or TLS tools before you start. The
sections below explain each idea, then repeat the commands.

## Why a virtual machine (and why not Docker)

The kit’s job is to behave like an operator on a VPS:

- create a system user (`useradd`)
- unpack a release under `/opt/<app>/<name>/`
- write a **systemd** unit and `systemctl enable --now`
- write **nginx** site files under `/etc/nginx/sites-available` (or `conf.d`)
- reload nginx with `systemctl`
- install PowerShell wrappers whose shebang is `#!/snap/bin/pwsh`

A normal Docker container is a process sandbox, not a little VPS. The usual
Ubuntu images do not run systemd as PID 1, and snap (which we use for
PowerShell) expects a full systemd machine. Getting both working in Docker
means privileged containers, cgroup mounts, and a lot of accidental debugging
of Docker instead of the kit.

A **virtual machine** boots a real Ubuntu kernel and userspace. Inside it,
`systemctl`, `snap`, `nginx`, and `useradd` are the same commands you will use
on the VPS.

Two popular “tiny Ubuntu VM on a Mac” tools are **Lima** and **Multipass**.
This repo standardised on Lima because:

- your Mac home directory is mounted in the guest at the **same path**, so
  `NVK_ROOT=/Users/you/dev/cursor/node-vps-kit` works without a separate
  `mount` step
- guest ports can be forwarded to Mac `localhost` (the browser on the Mac can
  talk to nginx in the VM)
- `brew install lima` does not install a privileged extra daemon
- the instance config can live in git (`scripts/lima-nvk.yaml`)

Multipass is a fine “spare Ubuntu cloud instance” if you prefer that mental
model. It is not what `lima-up.sh` wraps.

## What Lima is

Lima (Linux Machines) starts a Linux VM on your Mac using Apple’s
Virtualization.framework (`vmType: vz` in our YAML). You still edit files in
Cursor on macOS. The VM is a second computer that happens to share your home
folder (read-only) and some network ports.

Useful words:

- **Host** — the Mac.
- **Guest** (or **instance**) — the Ubuntu VM. Ours is named `nvk`.
- **`limactl`** — Lima’s command-line tool (installed by Homebrew).
- **Cloud image** — a preinstalled Ubuntu Server disk file Lima can boot
  without walking through the installer. See below.

Lima is **not** Docker, and it is **not** “Ubuntu running as a Mac app.” After
`lima-up.sh`, you open a shell *in Ubuntu* and run `sudo` there.

## Cloud images versus “normal Ubuntu Server”

When people say they downloaded Ubuntu Server, they usually mean the
**live-server ISO** from ubuntu.com (for example
`ubuntu-26.04-live-server-arm64.iso`). That file is an **installer**. You boot
it, answer Subiquity’s questions (disk, username, SSH), and only then have an
installed system.

Lima never runs that installer. It attaches a disk that is **already** an
installed OS, injects a first-boot config (cloud-init, next section), and
boots. So you need the **cloud image**: a disk-shaped file such as

`ubuntu-26.04-server-cloudimg-arm64.img`

That *is* Ubuntu Server: same `apt`, systemd, snap, and nginx. It is just
packaged for unattended first boot (OpenStack, Multipass, Lima, and similar
tools all use this contract).

| File | What it is | Use with Lima? |
|---|---|---|
| `ubuntu-26.04-live-server-*.iso` | Installer disc | No |
| `ubuntu-26.04-server-cloudimg-arm64.img` | Preinstalled Server disk (Apple Silicon) | Yes |
| `ubuntu-26.04-server-cloudimg-amd64.img` | Same, for Intel Macs | Yes |

Lima’s rule of thumb: the image must have **systemd** and **cloud-init**.

## What cloud-init is

Imagine you cloned a generic Ubuntu disk that has no idea who you are. On a
physical server you would sit at the console and create a user. On a public
cloud, there is no console workflow like that at first boot: the platform has
to inject “this SSH key is allowed, this username exists, this hostname is
`nvk`” *before* you can log in.

**cloud-init** is the program inside Ubuntu that reads that injected config on
first boot (and sometimes later). The cloud (or Lima) attaches a tiny
configuration drive; cloud-init notices it, creates your user, copies your SSH
public key into `~/.ssh/authorized_keys`, grants `sudo`, grows the disk, sets
the hostname, and can run extra scripts.

You do not write a cloud-init file for this kit. Lima generates one from
`scripts/lima-nvk.yaml` plus its own defaults (your Mac username, a Lima SSH
key under `~/.lima/_config/user`, mounts, and so on). That is why the guest
login matches your Mac username and why `limactl shell nvk` works without a
password.

If you booted a desktop ISO or a hand-installed disk that had never seen
cloud-init, Lima would not know how to create that login. The cloud image is
the Ubuntu build that expects this handshake.

cloud-init is **not** a replacement for this kit. It only prepares a bare
Ubuntu so you can SSH in. Installing nginx, Node, PowerShell, and your apps
still happens afterwards, with `apt`/`snap` and then `bootstrap.ps1` /
`install.ps1`.

## Get the cloud image (once)

The listing on [cloud-images.ubuntu.com](https://cloud-images.ubuntu.com/)
looks like every cloud vendor and CPU in the world. You want **one** file.

1. Open the **26.04 LTS release** directory (not `daily`, not the “image
   locator”):
   [https://cloud-images.ubuntu.com/releases/26.04/release/](https://cloud-images.ubuntu.com/releases/26.04/release/)
2. Download only the `.img` whose name is
   `ubuntu-26.04-server-cloudimg-<arch>.img`.

On Apple Silicon (check with `uname -m`; you want `arm64`):

[https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-arm64.img](https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-arm64.img)

On Intel Macs (`x86_64`):

[https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img](https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img)

Save it as, for example:

`~/Downloads/ubuntu-26.04-server-cloudimg-arm64.img`

**Ignore:** `.tar.gz`, `.squashfs`, `-root.tar.xz`, `-lxd`, `-azure`, `.vmdk`,
`.ova`, `.manifest`, `armhf`, `ppc64el`, `riscv64`, `s390x`, and `unpacked/`.
`arm64` is this Mac if `uname -m` prints `arm64`. `amd64` is Intel/AMD.
`armhf` is 32-bit ARM and will not boot.

Lima’s YAML uses the name `aarch64` for the same CPU Ubuntu calls `arm64`.

The image is on the order of 600–900 MB. `lima-up.sh` is written so Lima
**does not fetch** another copy from the network: it boots the file you
already downloaded. The first `lima-up.sh` still **copies** that file into
`~/.lima/nvk/` (local disk to local disk). Let it finish; it can take a few
minutes and uses extra disk space.

Do **not** start the VM with `limactl start template://ubuntu`. That template
downloads its own image and extra archives (for example nerdctl). Our YAML
turns containerd off for the same reason.

The cloud image is only the OS. **nginx, Node, and snap PowerShell are
installed later inside the guest** and need network on that first package
install. That is a smaller, separate download from the cloud image.

## Install Lima and start the guest

On the Mac (once):

```bash
brew install lima
```

From this repository, after the `.img` is fully downloaded:

```bash
cd /Users/raith/dev/cursor/node-vps-kit
./scripts/lima-up.sh
```

If the file is not in `~/Downloads` under the default name:

```bash
NVK_LIMA_IMAGE=/path/to/ubuntu-26.04-server-cloudimg-arm64.img ./scripts/lima-up.sh
```

The instance name defaults to `nvk` (`NVK_LIMA_INSTANCE` overrides it).
`scripts/lima-nvk.yaml` is the machine description: 2 CPUs, 4 GiB RAM, 40 GiB
disk, `vmType: vz`, no containerd, home mounted read-only, **vzNAT** (a guest
IP the Mac can ping), and port forwards for **80** and **443**.

Home is read-only on purpose. You edit the kit on the Mac; the guest must not
write into git. When you install an app, the kit writes under `/opt`, `/etc`,
`/usr/local`, and `/var/cache` on the **guest disk**, which is writable.

Running `./scripts/lima-up.sh` again only **starts** an existing instance. It
does not recreate the VM or re-copy the image.

Stop and start later:

```bash
limactl stop nvk
./scripts/lima-up.sh
# or: limactl start nvk
```

List instances:

```bash
limactl list
```

## How to run commands on the guest (including SSH)

The usual way is Lima’s helper, which already knows the key and port:

```bash
limactl shell nvk
```

One-shot commands (no interactive shell):

```bash
limactl shell nvk -- uname -a
limactl shell nvk -- ip -4 addr show lima0
```

Lima also runs OpenSSH in the guest and maps it to **localhost on the Mac**
(a high port such as 60022, not port 22 on the Mac). Password login is off.
The key is `~/.lima/_config/user`. Lima writes a ready-made SSH config:

```bash
ssh -F ~/.lima/nvk/ssh.config lima-nvk
```

To use plain `ssh lima-nvk` from any terminal, put this **at the top** of
`~/.ssh/config` on the Mac:

```
Include ~/.lima/*/ssh.config
```

Then:

```bash
ssh lima-nvk
```

The SSH destination name is `lima-<instance>`, so `lima-nvk` for instance
`nvk`. The guest username is your **Mac** username (cloud-init created it).

There is no graphical Ubuntu desktop in this setup. Everything is SSH or
`limactl shell`.

## How the Mac reaches nginx in the VM

Two mechanisms are enabled at once.

### 1. Port forwards (localhost)

Lima watches ports the guest listens on and can forward them to the Mac.
By default, automatic forwards often cover **1024–65535** only, so **80 and
443 would not show up on the Mac** unless we say so. Our YAML therefore has
static rules: Mac `0.0.0.0:80` → guest `:80`, and the same for **443**.
(`hostIP: 0.0.0.0` is what allows those privileged ports on macOS.)

After nginx is listening in the guest, on the Mac:

```text
http://127.0.0.1/
https://127.0.0.1/
```

For a hostname (needed for TLS certificates and for `server_name` in nginx),
add a line to the **Mac** `/etc/hosts` (not the guest’s):

```text
127.0.0.1 www.example.test
```

Edit with:

```bash
sudo nano /etc/hosts
```

Then browse to `http://www.example.test/` or `https://www.example.test/`.
The Mac thinks that name is itself; Lima forwards 80/443 into Ubuntu; nginx
in Ubuntu sees the `Host` header and proxies to Node on `127.0.0.1:<port>`
**inside the guest**.

### 2. vzNAT (guest IP)

`vzNAT` gives the VM an address on a virtual LAN that **only the Mac** can
reach (not your home router, not the public internet). Inspect it from the
Mac:

```bash
limactl shell nvk -- ip -4 addr show lima0
```

You can put that IP in `/etc/hosts` instead of `127.0.0.1` if you prefer
talking to the VM like a small VPS. Port forwards still help when you want
plain `https://www.example.test/` on the usual ports.

The VM is **not** a public website. Let’s Encrypt cannot see it from the
internet. That is why local TLS uses mkcert, not certbot (next major
section).

## First boot on Ubuntu: kit prerequisites

Open a guest shell:

```bash
limactl shell nvk
```

Install the same prerequisites the VPS needs. PowerShell **must** be the snap
so wrappers can use `#!/snap/bin/pwsh`.

```bash
sudo apt-get update
sudo apt-get install -y nginx tar curl ca-certificates
sudo snap install powershell --classic
```

Node must be **system-wide** (on `root`’s PATH), not only nvm in your user
account. The kit records the `node` binary path in the systemd unit. Install
a system Node ≥ the app’s `NodeMajor` (Proseden currently wants 20). Ubuntu’s
`nodejs` package may be new enough on 26.04; if `node -v` is too old, use a
NodeSource (or similar) **system** package, still not nvm.

Optional, after PowerShell works:

```bash
sudo snap refresh --hold powershell
```

Check:

```bash
node -v
nginx -v
pwsh -v
systemctl --version
```

Leave this shell open; the next commands run **in the guest**, with `sudo`.

## Install the kit and an app (`NVK_ROOT`)

Because home is mounted at the same path, the git checkout on the Mac is
already visible in the guest. You do **not** clone the kit inside the VM.
You point the scripts at that path with `NVK_ROOT` so you test the files you
are editing, not a stale copy under `/usr/local/lib`.

Adjust the path if your clone lives somewhere else.

Copy the kit onto the guest’s `/usr/local/lib/node-vps-kit` (does **not**
fetch GitHub):

```bash
sudo NVK_ROOT=/Users/raith/dev/cursor/node-vps-kit \
  pwsh -File /Users/raith/dev/cursor/node-vps-kit/bootstrap.ps1
```

Install an app instance from the same checkout (also does not refresh the
kit from GitHub):

```bash
sudo NVK_ROOT=/Users/raith/dev/cursor/node-vps-kit \
  pwsh -File /Users/raith/dev/cursor/node-vps-kit/install.ps1 \
    -App proseden -Name www -ServerName www.example.test -Port 3336
```

Later, update that instance:

```bash
sudo NVK_ROOT=/Users/raith/dev/cursor/node-vps-kit \
  pwsh -File /Users/raith/dev/cursor/node-vps-kit/update.ps1 \
    -App proseden -Name www
```

If you already bootstrapped, the PATH wrappers (`nvk-app-install`,
`nvk-update`, …) live in `/usr/local/sbin` **inside the guest**. Those
wrappers always invoke the **installed** copy under
`/usr/local/lib/node-vps-kit`, not your git tree. While you are changing kit
code, keep using `NVK_ROOT` + `pwsh -File …/install.ps1` as above.

`nvk-update` (from the installed copy) fetches this kit from GitHub. That is
the VPS operator flow, not the “I just edited `Nvk.psm1`” flow.

`KIT_REPO` / `KIT_REF` only matter when bootstrap/`nvk-update` **does** fetch
GitHub.

After install, systemd should be running Node in the **guest**. Check:

```bash
sudo systemctl status proseden-www
curl -sS http://127.0.0.1:3336/health
```

From the **Mac** browser, until TLS is set up, use `http://www.example.test/`
if `/etc/hosts` and the port-80 forward are in place (and nginx is up).

## Certbot versus mkcert

The kit’s post-install text on a VPS says, in spirit: point DNS at the
server, open 80/443, then `sudo certbot --nginx -d your.domain`. That is
correct **in production**. It is the wrong tool on a laptop VM.

### What both tools do

Browsers treat **HTTPS** as “the certificate chains to a CA I already
trust.” Without that, you get a warning, and cookies marked `Secure` may
not be stored.

**Certbot** talks to **Let’s Encrypt**, a public certificate authority. Let’s
Encrypt will only issue a certificate if it can prove you control the
**public** hostname. The usual proof (HTTP-01) is: “I fetched
`http://your.domain/.well-known/acme-challenge/…` from the internet and it
matched.” That requires:

- a real DNS name pointing at a **public** IP
- port 80 reachable from the internet

Your Lima VM is behind macOS NAT. The world cannot connect to it. HTTP-01
fails. DNS-01 (a TXT record on a real domain) can work in clever setups, but
it is extra accounts, APIs, and failure modes, and it still does not match
“toy hostname in `/etc/hosts`.”

**mkcert** is a **local** CA for development. You run `mkcert -install` once
on the Mac; it puts a small private CA into the Mac trust store (and Firefox
if you install the `nss` extra). Then `mkcert www.example.test` mints a
certificate **that this Mac already trusts**. No internet proof, no public
DNS. Browsers on **this** Mac accept `https://www.example.test/` without a
warning. Other people’s laptops do not, which is what you want for a
throwaway VM.

The Node process can stay on `http://127.0.0.1:3336` inside the guest, same
as on the VPS. **nginx terminates TLS** (port 443) and proxies to Node. That
matches production’s shape: the app sees `X-Forwarded-Proto: https` if nginx
is configured to send it (the kit’s site template already forwards
`X-Forwarded-Proto`).

Apps that set **secure cookies** (`PROSEDEN_SECURE_COOKIES=1` in Proseden’s
profile) only send those cookies on HTTPS. HTTP to `:80` will look like
“login does not stick.” Use HTTPS locally if you care about that behaviour.

### mkcert on the Mac, nginx in the guest

On the **Mac**:

```bash
brew install mkcert nss
mkcert -install
cd ~/Downloads
mkcert www.example.test
```

That writes `www.example.test.pem` and `www.example.test-key.pem` in the
current directory. Because the guest can **read** your home directory, nginx
inside Ubuntu can point at those files (adjust the user path):

`/Users/raith/Downloads/www.example.test.pem`
`/Users/raith/Downloads/www.example.test-key.pem`

The kit’s site file is HTTP-only (`listen 80`). After `nvk-app-install`,
edit the guest site (for example
`/etc/nginx/sites-available/proseden-www`) and add a `listen 443 ssl`
server (or a second `server { }` with the same `server_name`) using those
certificate paths. Then:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

On the Mac, keep `/etc/hosts` pointing `www.example.test` at `127.0.0.1`
(or the vzNAT address). Open `https://www.example.test/` in the browser.

A **self-signed** certificate you generate with `openssl` also encrypts the
pipe, but the Mac browser will warn on every visit unless you trust it by
hand. mkcert is the less painful local equivalent of “a CA the browser
likes.”

Do not run `certbot --nginx` against this VM expecting it to succeed the
way it does on a public VPS. Leave certbot for the real server.

## Command cheat sheet

**Mac — one-time**

```bash
brew install lima
# download ubuntu-26.04-server-cloudimg-arm64.img (or amd64) into ~/Downloads
cd /Users/raith/dev/cursor/node-vps-kit
./scripts/lima-up.sh
```

**Mac — everyday**

```bash
./scripts/lima-up.sh          # start if stopped
limactl shell nvk            # Ubuntu shell
limactl stop nvk             # stop the VM
limactl list
limactl shell nvk -- ip -4 addr show lima0
ssh -F ~/.lima/nvk/ssh.config lima-nvk
```

**Guest — prerequisites**

```bash
sudo apt-get update
sudo apt-get install -y nginx tar curl ca-certificates
sudo snap install powershell --classic
node -v && nginx -v && pwsh -v
```

**Guest — kit from this checkout**

```bash
sudo NVK_ROOT=/Users/raith/dev/cursor/node-vps-kit \
  pwsh -File /Users/raith/dev/cursor/node-vps-kit/bootstrap.ps1

sudo NVK_ROOT=/Users/raith/dev/cursor/node-vps-kit \
  pwsh -File /Users/raith/dev/cursor/node-vps-kit/install.ps1 \
    -App proseden -Name www -ServerName www.example.test -Port 3336

sudo NVK_ROOT=/Users/raith/dev/cursor/node-vps-kit \
  pwsh -File /Users/raith/dev/cursor/node-vps-kit/update.ps1 \
    -App proseden -Name www
```

**Mac — TLS for secure cookies**

```bash
brew install mkcert nss
mkcert -install
mkcert www.example.test
sudo nano /etc/hosts   # 127.0.0.1 www.example.test
```

Then add `listen 443 ssl` in the **guest** nginx site and `systemctl reload
nginx`.
