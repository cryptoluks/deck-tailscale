#!/usr/bin/env bash

# Error handler function.
error_handler() {
  echo "An error occurred on line $1 of the script."
  read -p "Press any key to exit." -n1
  exit 1
}

set -euo pipefail

# Trap any script error.
trap 'error_handler $LINENO' ERR

# Load system configuration variables.
source /etc/os-release

# Create and switch to a temporary directory.
temp_dir="$(mktemp -d)"
trap "rm -rf ${temp_dir}" EXIT
cd "${temp_dir}"

# Fetch the latest Tailscale version.
echo -n "Fetching Tailscale version..."
tailscale_info="$(curl -s 'https://pkgs.tailscale.com/stable/?mode=json')"
tarball_url="$(echo "$tailscale_info" | jq -r .Tarballs.amd64)"
version="$(echo "${tarball_url}" | cut -d_ -f2)"
echo "Version ${version}"

# Download and extract the Tailscale package.
echo -n "Downloading and extracting..."
curl -sS "https://pkgs.tailscale.com/stable/${tarball_url}" | tar xzf -
echo "Done."

extracted_dir="$(echo "${tarball}" | cut -d. -f1-3)"
test -d "${extracted_dir}"

# Set up target directory structure and organize files.
install_dir="tailscale/usr"
mkdir -p "${install_dir}/{bin,sbin,lib/{systemd/system,extension-release.d}}"
cp -rf "${extracted_dir}/tailscale" "${install_dir}/bin/tailscale"
cp -rf "${extracted_dir}/tailscaled" "${install_dir}/sbin/tailscaled"

# Create a systemd extension-release file.
echo -e "SYSEXT_LEVEL=1.0\nID=steamos\nVERSION_ID=${VERSION_ID}" > "${install_dir}/lib/extension-release.d/extension-release.tailscale"

# Manage system extensions: create, remove old, install new.
extensions_dir="/var/lib/extensions"
mkdir -p "${extensions_dir}"
rm -rf "${extensions_dir}/tailscale"
cp -rf tailscale "${extensions_dir}/"

# Set up systemd service.
cp -rf "${extracted_dir}/systemd/tailscaled.service" "/etc/systemd/system"

# Check and copy defaults if absent.
defaults_path="/etc/default/tailscaled"
[[ ! -f "${defaults_path}" ]] && cp -rf "${extracted_dir}/systemd/tailscaled.defaults" "${defaults_path}"

# Handle overrides if absent.
override_path="/etc/systemd/system/tailscaled.service.d/override.conf"
if [[ ! -f "${override_path}" ]]; then
  mkdir -p "$(dirname "${override_path}")"
  tee "${override_path}" > /dev/null <<OVERRIDE
[Service]
ExtensionDirectories=/var/lib/extensions/tailscale
OVERRIDE
fi

echo "Tailscale installation complete. Managing services..."

# Manage systemd-sysext service.
if systemctl is-enabled --quiet systemd-sysext && systemctl is-active --quiet systemd-sysext; then
  echo "systemd-sysext is enabled and active."
else
  systemctl enable systemd-sysext --now
fi

# Refresh and reload.
systemd-sysext refresh > /dev/null 2>&1
systemctl daemon-reload > /dev/null

# Manage tailscaled service.
if systemctl is-enabled --quiet tailscaled && systemctl is-active --quiet tailscaled; then
  echo "tailscaled is enabled and active. Restarting..."
  systemctl restart tailscaled
else
  systemctl enable tailscaled --now
fi

echo "Tailscale setup complete."
