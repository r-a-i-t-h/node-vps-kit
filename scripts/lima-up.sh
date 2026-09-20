#!/usr/bin/env bash
# Create (if needed) and start the Lima Ubuntu VM used to run this kit.
# Does not install nginx/Node/pwsh — do that inside the guest after first boot.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
YAML="${ROOT}/scripts/lima-nvk.yaml"
INSTANCE="${NVK_LIMA_INSTANCE:-nvk}"

die() {
  echo "lima-up: $*" >&2
  exit 1
}

if ! command -v limactl >/dev/null 2>&1; then
  die 'limactl not found (install: brew install lima)'
fi

host_arch="$(uname -m)"
case "${host_arch}" in
  arm64 | aarch64)
    lima_arch='aarch64'
    default_img="${HOME}/Downloads/ubuntu-26.04-server-cloudimg-arm64.img"
    ;;
  x86_64)
    lima_arch='x86_64'
    default_img="${HOME}/Downloads/ubuntu-26.04-server-cloudimg-amd64.img"
    ;;
  *)
    die "unsupported host arch ${host_arch}"
    ;;
esac

IMAGE="${NVK_LIMA_IMAGE:-${default_img}}"
IMAGE="${IMAGE/#\~/${HOME}}"

instance_exists() {
  limactl list --format '{{.Name}}' 2>/dev/null | grep -qx "${INSTANCE}"
}

instance_running() {
  [[ "$(limactl list --format '{{if eq .Name "'"${INSTANCE}"'"}}{{.Status}}{{end}}' 2>/dev/null | tr -d '[:space:]')" == 'Running' ]]
}

if instance_running; then
  echo "lima-up: instance '${INSTANCE}' already running"
elif instance_exists; then
  echo "lima-up: starting existing instance '${INSTANCE}'"
  limactl start "${INSTANCE}"
else
  [[ -f "${IMAGE}" ]] || die "cloud image not found: ${IMAGE}

Download Ubuntu 26.04 LTS cloudimg for this Mac (${lima_arch}) into Downloads,
or set NVK_LIMA_IMAGE to the file you saved.

  arm64:  https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-arm64.img
  x86_64: https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img

Use the .img named ubuntu-26.04-server-cloudimg-<arch>.img — not .tar.gz, -lxd, or -azure."

  echo "lima-up: creating '${INSTANCE}' from ${IMAGE}"
  limactl start \
    --name="${INSTANCE}" \
    --yes \
    --vm-type=vz \
    --containerd=none \
    --network=vzNAT \
    --set ".images = [{\"location\":\"${IMAGE}\",\"arch\":\"${lima_arch}\"}]" \
    "${YAML}"
fi

echo
echo "lima-up: guest is up."
echo "  shell:  limactl shell ${INSTANCE}"
echo "  ssh:    ssh -F ${HOME}/.lima/${INSTANCE}/ssh.config lima-${INSTANCE}"
echo
echo "This checkout is mounted at the same path inside the VM:"
echo "  ${ROOT}"
echo
echo "Next (inside the guest): install nginx, Node, and snap PowerShell, then:"
echo "  sudo NVK_ROOT=${ROOT} pwsh -File ${ROOT}/bootstrap.ps1"
echo
echo "nginx on the Mac: http://127.0.0.1/  (and :443 once TLS is on the guest)"
echo "Guest IP (vzNAT): limactl shell ${INSTANCE} -- ip -4 addr show lima0"
