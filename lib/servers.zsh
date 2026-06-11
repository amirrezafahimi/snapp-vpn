# Server management
# =============================================================================

# List available VPN servers
vpn_list_servers() {
    echo "🌐 Available VPN Servers"
    echo "======================="
    
    local current_server_name=$(vpn_get_current_server_name)
    
    local server_name server_url status_icon switch_hint=""

    for server_name in ${VPN_SERVER_ORDER[@]}; do
        server_url="${VPN_SERVERS[$server_name]}"
        [[ -z "$server_url" ]] && continue
        status_icon="📍"
        switch_hint+="${switch_hint:+, }$server_name"

        if [[ "$server_name" == "$current_server_name" ]]; then
            status_icon="👉"
            echo "$status_icon $server_name: $server_url (CURRENT)"
        else
            echo "$status_icon $server_name: $server_url"
        fi
    done

    echo ""
    echo "💡 Use 'vpn_switch <name>' to change servers (available: $switch_hint)"
    echo "💡 Current server: $current_server_name"
}

# Switch VPN server
vpn_switch() {
    local new_server="$1"
    
    if [[ -z "$new_server" ]]; then
        echo "🌐 Current server: $(vpn_get_current_server_name) ($VPN_CURRENT_SERVER)"
        echo ""
        vpn_list_servers
        return 1
    fi
    
    # Check if server exists
    if [[ -z "${VPN_SERVERS[$new_server]}" ]]; then
        echo "❌ Server '$new_server' not found"
        echo ""
        vpn_list_servers
        return 1
    fi
    
    local old_server=$(vpn_get_current_server_name)
    local new_server_url="${VPN_SERVERS[$new_server]}"
    
    # Save current server to config file
    echo "VPN_CURRENT_SERVER=\"$new_server_url\"" > "$VPN_CONFIG_FILE"
    export VPN_CURRENT_SERVER="$new_server_url"
    
    echo "🔄 Switched from $old_server to $new_server"
    echo "🌐 New server: $new_server_url"
    
    # Check if currently connected and ask about reconnection
    if vpn_status >/dev/null 2>&1; then
        echo "⚠️  You are currently connected to VPN"
        read -p "🔄 Do you want to reconnect to the new server? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "🔌 Disconnecting from $old_server..."
            vpn_disconnect
            sleep 2
            echo "🔗 Connecting to $new_server..."
            vpn_connect_background
        else
            echo "💡 New server will be used on next connection"
        fi
    else
        echo "💡 Use 'vpn' or 'vpnbg' to connect to the new server"
    fi
    
    _log "Server switched from $old_server to $new_server"
}
