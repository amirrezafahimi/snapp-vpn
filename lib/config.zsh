# Snapp VPN — configuration and shared helpers
# User overrides: ~/.config/snapp-vpn/config (see config.example)

SNAPP_VPN_CONFIG_DIR="${SNAPP_VPN_CONFIG_DIR:-$HOME/.config/snapp-vpn}"
SNAPP_VPN_CONFIG_FILE="${SNAPP_VPN_CONFIG_FILE:-$SNAPP_VPN_CONFIG_DIR/config}"

VPN_LOGFILE="${SNAPP_VPN_LOGFILE:-$HOME/.vpn_connection.log}"
VPN_PIDFILE="${SNAPP_VPN_PIDFILE:-$HOME/.vpn_connection.pid}"
VPN_CONFIG_FILE="${SNAPP_VPN_STATE_FILE:-$HOME/.vpn_config}"
VPN_CERTS_FILE="${SNAPP_VPN_CERTS_FILE:-$HOME/.vpn_servercerts}"
VPN_STOP_FLAG_FILE="${SNAPP_VPN_STOP_FLAG:-$HOME/.vpn_stop_requested}"

# Default servers (override in config file)
typeset -gA VPN_SERVERS
if (( ${#VPN_SERVERS[@]} == 0 )); then
    VPN_SERVERS=(
        ["site1"]="site1.snapp.cab:43443"
        ["site2"]="site2.snapp.cab:43443"
        ["site3"]="site3.dc.snappcloud.io:43443"
    )
fi

VPN_SERVER_ORDER=(site1 site2 site3)

# Optional internal hosts for vpn_health (override in user config)
typeset -ga VPN_HEALTH_ENDPOINTS
if (( ${#VPN_HEALTH_ENDPOINTS[@]} == 0 )); then
    VPN_HEALTH_ENDPOINTS=(
        "172.31.1.1"
        "10.21.233.2"
        "192.168.16.4"
        "172.31.4.254"
        "172.30.90.2"
    )
fi

KEYCHAIN_VPN_SERVICE="${SNAPP_VPN_KEYCHAIN_SERVICE:-snapp-vpn}"
KEYCHAIN_TOTP_SERVICE="${SNAPP_VPN_KEYCHAIN_TOTP:-snapp-totp}"
KEYCHAIN_TOTP_ACCOUNT="${SNAPP_VPN_TOTP_ACCOUNT:-totp-secret}"

if [[ -f "$SNAPP_VPN_CONFIG_FILE" ]]; then
    source "$SNAPP_VPN_CONFIG_FILE"
fi

VPN_USER="${SNAPP_VPN_USER:-${VPN_USER:-}}"
VPN_CURRENT_SERVER="${VPN_CURRENT_SERVER:-${VPN_SERVERS[site1]}}"

if [[ -z "$VPN_USER" ]]; then
    echo "❌ SNAPP_VPN_USER / VPN_USER not set. Copy config.example to $SNAPP_VPN_CONFIG_FILE" >&2
    return 1 2>/dev/null || exit 1
fi

# Ordered server names for listing (override in user config)
typeset -ga VPN_SERVER_ORDER
if (( ${#VPN_SERVER_ORDER[@]} == 0 )); then
    VPN_SERVER_ORDER=(${(ko)VPN_SERVERS})
fi

snapp_vpn_server_names() {
    print -r -- ${VPN_SERVER_ORDER[@]}
}

vpn_get_current_server_name() {
    local name
    for name in ${VPN_SERVER_ORDER[@]}; do
        [[ "${VPN_SERVERS[$name]}" == "$VPN_CURRENT_SERVER" ]] && { echo "$name"; return 0 }
    done
    echo "unknown"
}


_load_server_config() {
    if [[ -f "$VPN_CONFIG_FILE" ]]; then
        source "$VPN_CONFIG_FILE"
    fi
}

# Load cached server certificate pins
_load_server_certs() {
    typeset -gA VPN_SERVERCERTS

    if [[ ! -f "$VPN_CERTS_FILE" ]]; then
        return 0
    fi

    while IFS='=' read -r server pin; do
        [[ -z "$server" || -z "$pin" ]] && continue
        server="${server//\"/}"
        server="${server//[[:space:]]/}"
        pin=$(print -r -- "$pin" | tr -d '\r' | grep -oE 'pin-sha256:[A-Za-z0-9+/=]+' | tail -n 1)
        # Ignore corrupted/empty pins (47DE... is SHA256 of empty input).
        if [[ ! "$pin" =~ ^pin-sha256:[A-Za-z0-9+/=]+$ || "$pin" == "pin-sha256:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=" ]]; then
            continue
        fi
        VPN_SERVERCERTS["$server"]="$pin"
    done < "$VPN_CERTS_FILE"
}

# Persist server certificate pins to disk
_save_server_certs() {
    : > "$VPN_CERTS_FILE"
    for server in "${(@k)VPN_SERVERCERTS}"; do
        server="${server//\"/}"
        echo "${server}=${VPN_SERVERCERTS[$server]}" >> "$VPN_CERTS_FILE"
    done
}

# Reconnect stop-flag helpers (used by vpnoff to stop auto-reconnect loop)
_vpn_set_stop_request() {
    echo "1" > "$VPN_STOP_FLAG_FILE"
}

_vpn_clear_stop_request() {
    rm -f "$VPN_STOP_FLAG_FILE"
}

_vpn_stop_requested() {
    [[ -f "$VPN_STOP_FLAG_FILE" ]]
}

# Remove host routes left by a previous VPN session (common cause of EADDRNOTAVAIL).
# OpenConnect adds host routes to the VPN gateway; after disconnect they can point at the
# wrong next-hop (e.g. 192.168.10.1) while en0 is on another network (e.g. 172.31.95.x).
_vpn_cleanup_stale_routes() {
    local site url host ip gw removed=0

    # Never tear down routes while the tunnel process is still running.
    if pgrep -f "openconnect.*--protocol=fortinet" >/dev/null 2>&1; then
        return 0
    fi

    for site in ${VPN_SERVER_ORDER[@]}; do
        url="${VPN_SERVERS[$site]:-}"
        [[ -z "$url" ]] && continue
        host="${url%%:*}"
        ip=$(dig +short "$host" A 2>/dev/null | head -1)
        [[ -z "$ip" ]] && continue

        # Any host-specific route to the VPN server IP is stale once disconnected.
        if ! netstat -rn 2>/dev/null | awk -v ip="$ip" '$1 == ip { found=1 } END { exit !found }'; then
            continue
        fi

        gw=$(route -n get "$ip" 2>/dev/null | awk '/gateway:/{print $2; exit}')
        echo "🧹 Removing stale host route: $ip -> ${gw:-?} (use default/LAN path to reach VPN)"
        if sudo route delete -host "$ip" 2>/dev/null || sudo route delete "$ip" 2>/dev/null; then
            ((removed++))
        fi
    done

    if (( removed > 0 )); then
        _log "Removed $removed stale VPN host route(s)"
    fi
}

# Validate that a pin string is a real non-empty pin-sha256 value.
# The value 47DEQpj... is SHA256 of empty input and must never be used.
_valid_cert_pin() {
    local pin="$1"
    [[ -n "$pin" ]] \
        && [[ "$pin" =~ ^pin-sha256:[A-Za-z0-9+/=]{20,}$ ]] \
        && [[ "$pin" != "pin-sha256:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=" ]]
}

# Cache a discovered pin for a server and persist to disk.
_cache_server_cert_pin() {
    local server="$1"
    local pin="$2"
    # Strip accidental quotes/whitespace from keys (can happen if cache file was corrupted).
    server="${server//\"/}"
    server="${server//[[:space:]]/}"
    # Take last valid pin line if the capture file had noise or multiple matches.
    pin=$(print -r -- "$pin" | tr -d '\r' | grep -oE 'pin-sha256:[A-Za-z0-9+/=]+' | tail -n 1)
    if _valid_cert_pin "$pin"; then
        VPN_SERVERCERTS["$server"]="$pin"
        _save_server_certs
        echo "✅ Certificate pin cached for $server: $pin"
    fi
}

# Return the cached valid pin for a server, or empty string.
_cached_cert_pin() {
    local pin="${VPN_SERVERCERTS[$1]:-}"
    _valid_cert_pin "$pin" && echo "$pin" || true
}

# Initialize configuration on load
_load_server_config
_load_server_certs

# =============================================================================

