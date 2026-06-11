# Connection management
# =============================================================================

# Main connection function with certificate trust and timing fixes
vpn_connect() {
    local _route_retry="${1:-0}"
    _log "Attempting VPN connection..."
    
    # Check if already connected
    if vpn_status >/dev/null 2>&1; then
        echo "✅ VPN already connected!"
        vpn_status
        return 0
    fi
    
    # Verify expect is installed
    if ! command -v expect >/dev/null 2>&1; then
        echo "❌ 'expect' is required but not installed"
        echo "💡 Install with: brew install expect"
        return 1
    fi
    
    # Get credentials
    if ! _get_credentials; then
        return 1
    fi
    
    echo "🔐 Connecting to Snapp VPN..."
    echo "🌐 Server: $(vpn_get_current_server_name) ($VPN_CURRENT_SERVER)"

    _vpn_cleanup_stale_routes

    local server_cert_pin
    server_cert_pin=$(_cached_cert_pin "$VPN_CURRENT_SERVER")

    local servercert_arg=""
    if [[ -n "$server_cert_pin" ]]; then
        servercert_arg="--servercert=$server_cert_pin"
        echo "🔒 Using cached certificate pin..."
    else
        echo "🔍 No cached pin — will auto-accept and cache for next time..."
    fi

    # Temp file used by expect to hand the discovered pin back to the shell.
    local pin_capture_file
    pin_capture_file=$(mktemp)

    expect -c "
        set timeout 180
        log_user 1
        set pin_file {$pin_capture_file}
        set connected 0

        spawn sudo env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy -u SOCKS_PROXY -u SOCKS5_PROXY -u socks_proxy -u socks5_proxy openconnect --protocol=fortinet \
                               --user=$VPN_USER \
                               --server=$VPN_CURRENT_SERVER \
                               $servercert_arg \
                               --no-dtls

        expect {
            -re {pin-sha256:[A-Za-z0-9+/=]+} {
                set fd [open \$pin_file w]
                puts \$fd \$expect_out(0,string)
                close \$fd
                exp_continue
            }
            \"None of the\" {
                puts \"🔄 Cached pin no longer valid, clearing...\"
                exit 2
            }
            \"Please enter 'yes' to accept\" {
                puts \"🔑 Auto-accepting server certificate...\"
                send \"yes\r\"
                exp_continue
            }
            \"Enter 'yes' to accept, 'no' to abort\" {
                puts \"🔑 Auto-accepting server certificate...\"
                send \"yes\r\"
                exp_continue
            }
            \"anything else to view:\" {
                puts \"🔑 Auto-accepting server certificate...\"
                send \"yes\r\"
                exp_continue
            }
            \"Password:\" {
                puts \"✅ Sending password...\"
                send \"$VPN_PASSWORD\r\"
                exp_continue
            }
            \"Answer:\" {
                puts \"🔑 Generating fresh OTP...\"
                set otp [exec oathtool -b --totp \"$VPN_TOTP_SECRET\"]
                puts \"✅ Sending OTP (first time): \$otp\"
                send \"\$otp\r\"
                exp_continue
            }
            \"credential:\" {
                puts \"✅ Sending OTP (second time): \$otp\"
                send \"\$otp\r\"
                exp_continue
            }
            \"Got Legacy IP address\" {
                puts \"🎉 VPN Connected Successfully!\"
                puts \"🔗 Connection established - you can now use the VPN\"
                puts \"🛑 Press Ctrl+C to disconnect or close this terminal\"
                set connected 1
                set timeout -1
                exp_continue
            }
            \"Configured as\" {
                puts \"🎯 VPN configuration complete\"
                set timeout -1
                exp_continue
            }
            \"Session authentication will expire\" {
                puts \"⏰ Session expiry noted\"
                set connected 1
                set timeout -1
                exp_continue
            }
            \"Detected dead peer!\" {
                puts \"⚠️ VPN tunnel dropped; waiting for reconnect result...\"
                exp_continue
            }
            \"svrhello status was\" {
                puts \"❌ Server rejected authentication - OTP timing issue\"
                exit 1
            }
            \"Can't assign requested address\" {
                puts \"❌ Network error: stale VPN route or bad gateway (not password/OTP)\"
                exit 11
            }
            \"Failed to connect to host\" {
                puts \"❌ Cannot reach VPN server host (routing/DNS), not authentication\"
                exit 11
            }
            \"Failed to open HTTPS connection\" {
                puts \"❌ Cannot open HTTPS to VPN server (routing/network)\"
                exit 11
            }
            \"Failed to complete authentication\" {
                puts \"❌ Authentication failed (or connection failed before login)\"
                exit 1
            }
            \"Idle timeout is\" {
                puts \"🎯 Connection established with idle timeout\"
                set connected 1
                set timeout -1
                exp_continue
            }
            timeout {
                puts \"❌ Connection setup timed out\"
                exit 1
            }
            eof {
                if {\$connected == 1} {
                    puts \"⚠️ VPN session ended after being connected\"
                    exit 10
                }
                exit 1
            }
        }

    "
    local connect_exit=$?

    # Cache any pin OpenConnect told us about during this session.
    if [[ -s "$pin_capture_file" ]]; then
        local discovered_pin
        discovered_pin=$(tr -d '\r' < "$pin_capture_file" | grep -oE 'pin-sha256:[A-Za-z0-9+/=]+' | tail -n 1)
        [[ -n "$discovered_pin" ]] && _cache_server_cert_pin "$VPN_CURRENT_SERVER" "$discovered_pin"
    fi
    rm -f "$pin_capture_file"

    # Stale cached pin: clear it and retry once without --servercert.
    if [[ $connect_exit -eq 2 ]]; then
        unset "VPN_SERVERCERTS[$VPN_CURRENT_SERVER]"
        _save_server_certs
        echo "🔄 Retrying with fresh certificate discovery..."
        vpn_connect
        return $?
    fi

    # Stale host route / routing failure: clean routes and retry once.
    if [[ $connect_exit -eq 11 && $_route_retry -eq 0 ]]; then
        _log "VPN connect failed: routing/network (exit 11)"
        echo "💡 Stale routes from a previous VPN session are a common cause on macOS."
        _vpn_cleanup_stale_routes
        echo "🔄 Retrying connection after route cleanup..."
        vpn_connect 1
        return $?
    fi

    if [[ $connect_exit -eq 10 ]]; then
        _log "VPN tunnel dropped; reconnect requested"
        return 10
    elif [[ $connect_exit -eq 0 ]]; then
        _log "VPN connection successful"
        _notify "VPN Connected" "Successfully connected to Snapp VPN"
    else
        _log "VPN connection failed"
        _notify "VPN Failed" "Failed to connect to Snapp VPN"
        return 1
    fi
}

# Smart connect - only connect if not already connected
vpn_smart_connect() {
    # New explicit connect should clear any previous manual stop request.
    _vpn_clear_stop_request

    if vpn_status >/dev/null 2>&1; then
        echo "✅ VPN already connected and healthy!"
        return 0
    fi

    echo "🔄 VPN not connected, initiating connection..."
    local reconnect_attempt=0
    while true; do
        if _vpn_stop_requested; then
            echo "🛑 Reconnect loop stopped by user request"
            return 0
        fi

        vpn_connect
        local rc=$?

        if [[ $rc -eq 10 ]]; then
            if _vpn_stop_requested; then
                echo "🛑 Reconnect loop stopped by user request"
                return 0
            fi
            ((reconnect_attempt++))
            local wait_seconds=$(( reconnect_attempt < 5 ? reconnect_attempt * 5 : 25 ))
            echo "🔁 VPN disconnected unexpectedly. Reconnecting in ${wait_seconds}s (attempt ${reconnect_attempt})..."
            sleep "$wait_seconds"
            continue
        fi

        return $rc
    done
}

# Graceful disconnect
vpn_disconnect() {
    echo "🔌 Disconnecting VPN..."
    echo "🌐 Server: $(vpn_get_current_server_name) ($VPN_CURRENT_SERVER)"

    # Signal reconnect loops to stop before killing the tunnel process.
    _vpn_set_stop_request

    local pids
    pids=$(pgrep -f "openconnect.*--protocol=fortinet" 2>/dev/null || true)

    if [[ -n "$pids" ]]; then
        echo "📤 Sending graceful shutdown signal..."
        while IFS= read -r pid; do
            [[ -z "$pid" ]] && continue
            sudo kill -TERM "$pid" 2>/dev/null || true
        done <<< "$pids"

        # Wait up to 10 seconds for graceful shutdown
        local countdown=10
        while [[ $countdown -gt 0 ]]; do
            local still_running
            still_running=$(pgrep -f "openconnect.*--protocol=fortinet" 2>/dev/null || true)
            [[ -z "$still_running" ]] && break
            echo "⏳ Waiting for shutdown... ($countdown seconds)"
            sleep 1
            ((countdown--))
        done

        # Force kill if still running
        local remaining
        remaining=$(pgrep -f "openconnect.*--protocol=fortinet" 2>/dev/null || true)
        if [[ -n "$remaining" ]]; then
            echo "💀 Force killing remaining VPN process(es)..."
            while IFS= read -r pid; do
                [[ -z "$pid" ]] && continue
                sudo kill -KILL "$pid" 2>/dev/null || true
            done <<< "$remaining"
        fi

        echo "✅ VPN disconnected"
        _log "VPN disconnected manually from $(vpn_get_current_server_name)"
        _notify "VPN Disconnected" "VPN connection terminated"
    else
        echo "ℹ️  VPN was not connected"
    fi

    _vpn_cleanup_stale_routes
}

# =============================================================================

