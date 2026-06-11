#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${HOME}/.config/snapp-vpn"
CONFIG_FILE="${CONFIG_DIR}/config"
ZSHRC="${HOME}/.zshrc"
MARKER="# Snapp VPN toolkit"

mkdir -p "${CONFIG_DIR}"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  cp "${ROOT}/config.example" "${CONFIG_FILE}"
  echo "Created ${CONFIG_FILE} — edit SNAPP_VPN_USER before connecting."
else
  echo "Config already exists: ${CONFIG_FILE}"
fi

SOURCE_BLOCK="${MARKER}
export SNAPP_VPN_ROOT=\"${ROOT}\"
[ -f \"\$SNAPP_VPN_ROOT/snapp-vpn.zsh\" ] && source \"\$SNAPP_VPN_ROOT/snapp-vpn.zsh\""

if grep -qF "${MARKER}" "${ZSHRC}" 2>/dev/null; then
  echo "Already configured in ${ZSHRC}"
else
  printf '\n%s\n' "${SOURCE_BLOCK}" >> "${ZSHRC}"
  echo "Appended Snapp VPN source block to ${ZSHRC}"
fi

chmod +x "${ROOT}/snapp-vpn.zsh"

echo ""
echo "Done. Next steps:"
echo "  1. Edit ${CONFIG_FILE}"
echo "  2. source ~/.zshrc"
echo "  3. vpn_setup    # store password + TOTP in Keychain"
echo "  4. vpn          # connect"
