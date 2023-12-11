#!/usr/bin/env bash

set -euo pipefail

error_exit() {
  echo "Error on line $1. Exiting."
  read -p "Press any key to exit." -n1
  exit 1
}
trap 'error_exit $LINENO' ERR

source /etc/os-release
temp_dir=$(mktemp -d)
trap "rm -rf ${temp_dir}" EXIT
cd "${temp_dir}"

echo -n "Fetching Tailscale version..."
tailscale_info=$(curl -s 'https://pkgs.tailscale.com/stable/?mode=json')
tarball_url=$(echo "$tailscale_info" | jq -r .Tarballs.amd64)
version=$(cut -d_ -f2 <<< "${tarball_url}")
echo "Version ${version}"

echo -n "Downloading Tailscale..."
curl "https://pkgs.tailscale.com/stable/${tarball_url}" | tar xzf -
echo "Download complete."

extracted_dir=$(basename "${tarball_url}" .tgz)
test -d "${extracted_dir}"

install_dir="tailscale/usr"
mkdir -p ${install_dir}/{bin,sbin,lib/{systemd/system,extension-release.d}}
cp -f "${extracted_dir}/tailscale" "${install_dir}/bin"
cp -f "${extracted_dir}/tailscaled" "${install_dir}/sbin"
echo "ID=steamos\nVERSION_ID=${VERSION_ID}" > "${install_dir}/lib/extension-release.d/extension-release.tailscale"

extensions_dir="/var/lib/extensions"
mkdir -p "${extensions_dir}"
rm -rf "${extensions_dir}/tailscale"
cp -rf tailscale "${extensions_dir}/"

cp -f "${extracted_dir}/systemd/tailscaled.service" "/etc/systemd/system"

defaults_path="/etc/default/tailscaled"
[[ ! -f "${defaults_path}" ]] && cp -f "${extracted_dir}/systemd/tailscaled.defaults" "${defaults_path}"

override_path="/etc/systemd/system/tailscaled.service.d/override.conf"
if [[ ! -f "${override_path}" ]]; then
  mkdir -p "$(dirname "${override_path}")"
  cat > "${override_path}" <<OVERRIDE
[Service]
ExtensionDirectories=/var/lib/extensions/tailscale
OVERRIDE
fi

echo "Tailscale installation complete. Configuring services..."

if systemctl is-enabled --quiet systemd-sysext && systemctl is-active --quiet systemd-sysext; then
  echo "systemd-sysext is already enabled and active."
else
  echo "Enabling and activating systemd-sysext..."
  systemctl enable systemd-sysext --now
fi

systemd-sysext refresh > /dev/null 2>&1
systemctl daemon-reload > /dev/null

if systemctl is-enabled --quiet tailscaled && systemctl is-active --quiet tailscaled; then
  echo "Restarting tailscaled service..."
  systemctl restart tailscaled
else
  echo "Enabling and starting tailscaled service..."
  systemctl enable tailscaled --now
fi

echo "Tailscale setup complete. Starting Tailscale..."
tailscale up --qr --operator=deck --ssh --accept-dns=true
