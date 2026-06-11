#!/usr/bin/env zsh
# Snapp VPN toolkit — shell entrypoint
# Source from ~/.zshrc: source "$SNAPP_VPN_ROOT/snapp-vpn.zsh"

SNAPP_VPN_ROOT="${SNAPP_VPN_ROOT:-${${(%):-%x}:A:h}}"

_snapp_vpn_source() {
    local f="$1"
    [[ -f "$f" ]] || { echo "snapp-vpn: missing $f" >&2; return 1; }
    source "$f"
}

_snapp_vpn_source "$SNAPP_VPN_ROOT/lib/config.zsh" || return 1
_snapp_vpn_source "$SNAPP_VPN_ROOT/lib/servers.zsh"
_snapp_vpn_source "$SNAPP_VPN_ROOT/lib/credentials.zsh"
_snapp_vpn_source "$SNAPP_VPN_ROOT/lib/core.zsh"
_snapp_vpn_source "$SNAPP_VPN_ROOT/lib/monitor.zsh"
_snapp_vpn_source "$SNAPP_VPN_ROOT/lib/connect.zsh"
_snapp_vpn_source "$SNAPP_VPN_ROOT/lib/advanced.zsh"
_snapp_vpn_source "$SNAPP_VPN_ROOT/lib/aliases.zsh"

trap 'unset VPN_PASSWORD VPN_TOTP_SECRET' EXIT

if [[ "${ZSH_EVAL_CONTEXT:-}" != *:file ]] && [[ "${(%):-%x}" == "$0" ]] && [[ $# -eq 0 ]]; then
    vpn_help
fi
