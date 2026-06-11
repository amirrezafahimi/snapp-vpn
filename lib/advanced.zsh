# Advanced features and debugging
# =============================================================================

# Background connection (stays connected without terminal)
vpn_connect_background() {
    _log "Attempting background VPN connection..."
    
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
    
    echo "🔐 Connecting to Snapp VPN in background..."
    echo "🌐 Server: $(vpn_get_current_server_name) ($VPN_CURRENT_SERVER)"
    echo "🔍 This will run in background and stay connected"

    local server_cert_pin
    server_cert_pin=$(_cached_cert_pin "$VPN_CURRENT_SERVER")

    local servercert_arg=""
    if [[ -n "$server_cert_pin" ]]; then
        servercert_arg="--servercert=$server_cert_pin"
        echo "🔒 Using cached certificate pin..."
    else
        echo "🔍 No cached pin — will auto-accept and cache for next time..."
    fi

    # Generate OTP
    local otp
    otp=$(_generate_otp)
    echo "🔑 Generated OTP: $otp"
    echo "🚀 Starting background connection..."

    local pin_capture_file
    pin_capture_file=$(mktemp)

    # Create temporary expect script
    local temp_script
    temp_script=$(mktemp)
    cat > "$temp_script" << EOF
#!/usr/bin/expect
set timeout 180
log_user 1
set pin_file {$pin_capture_file}

spawn sudo env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy -u SOCKS_PROXY -u SOCKS5_PROXY -u socks_proxy -u socks5_proxy openconnect --protocol=fortinet \\
                       --user=$VPN_USER \\
                       --server=$VPN_CURRENT_SERVER \\
                       $servercert_arg \\
                       --no-dtls \\
                       --background

expect {
    -re {pin-sha256:[A-Za-z0-9+/=]+} {
        set fd [open \$pin_file w]
        puts \$fd \$expect_out(0,string)
        close \$fd
        exp_continue
    }
    "None of the" {
        puts "🔄 Cached pin no longer valid, clearing..."
        exit 2
    }
    "Please enter 'yes' to accept" {
        send "yes\\r"
        exp_continue
    }
    "Enter 'yes' to accept, 'no' to abort" {
        send "yes\\r"
        exp_continue
    }
    "anything else to view:" {
        send "yes\\r"
        exp_continue
    }
    "Password:" {
        puts "✅ Sending password..."
        send "$VPN_PASSWORD\\r"
        exp_continue
    }
    "Answer:" {
        puts "✅ Sending OTP (first time)..."
        send "$otp\\r"
        exp_continue
    }
    "credential:" {
        puts "✅ Sending OTP (second time)..."
        send "$otp\\r"
        exp_continue
    }
    "Got Legacy IP address" {
        puts "🎉 Background VPN Connected Successfully!"
        exit 0
    }
    "Continuing in background" {
        puts "🎯 VPN running in background"
        exit 0
    }
    timeout {
        puts "❌ Background connection timed out"
        exit 1
    }
    eof {
        exit 0
    }
}
EOF

    expect "$temp_script"
    local connect_exit=$?
    rm -f "$temp_script"

    # Cache any pin discovered during this session.
    if [[ -s "$pin_capture_file" ]]; then
        local discovered_pin
        discovered_pin=$(tr -d '\r' < "$pin_capture_file" | grep -oE 'pin-sha256:[A-Za-z0-9+/=]+' | tail -n 1)
        [[ -n "$discovered_pin" ]] && _cache_server_cert_pin "$VPN_CURRENT_SERVER" "$discovered_pin"
    fi
    rm -f "$pin_capture_file"

    # Stale pin: clear and retry once.
    if [[ $connect_exit -eq 2 ]]; then
        unset "VPN_SERVERCERTS[$VPN_CURRENT_SERVER]"
        _save_server_certs
        echo "🔄 Retrying with fresh certificate discovery..."
        vpn_connect_background
        return $?
    fi

    if [[ $connect_exit -eq 0 ]]; then
        _log "Background VPN connection successful"
        _notify "VPN Connected" "Background VPN connection established"
        echo "✅ VPN connected in background!"
        echo "💡 Use 'vpns' to check status, 'vpnoff' to disconnect"
    else
        _log "Background VPN connection failed"
        _notify "VPN Failed" "Background VPN connection failed"
        return 1
    fi
}

# Connection with proper certificate validation (alternative to --no-cert-check)
vpn_connect_secure() {
    echo "🔐 Secure VPN Connection (with certificate validation)..."
    
    if ! _get_credentials; then
        return 1
    fi
    
    # Get the current certificate fingerprint
    echo "🔍 Discovering current certificate fingerprint..."
    local cert_fingerprint=$(timeout 10 openssl s_client -connect $(echo $VPN_CURRENT_SERVER | sed 's/:/ /') -servername $(echo $VPN_CURRENT_SERVER | cut -d: -f1) < /dev/null 2>/dev/null | \
                             openssl x509 -fingerprint -sha256 -noout 2>/dev/null | \
                             sed 's/SHA256 Fingerprint=//' | tr -d ':' | tr '[:upper:]' '[:lower:]')
    
    if [[ -z "$cert_fingerprint" ]]; then
        echo "❌ Failed to get certificate fingerprint"
        echo "💡 Falling back to standard connection mode"
        vpn_connect
        return $?
    fi
    
    echo "🔑 Using certificate: $cert_fingerprint"
    
    expect -c "
        set timeout 180
        log_user 1
        
        spawn sudo env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy -u SOCKS_PROXY -u SOCKS5_PROXY -u socks_proxy -u socks5_proxy openconnect --protocol=fortinet \
                               --user=$VPN_USER \
                               --server=$VPN_CURRENT_SERVER \
                               --servercert=$cert_fingerprint \
                               --no-dtls
        
        expect {
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
                puts \"🎉 Secure VPN Connected Successfully!\"
                exp_continue
            }
            \"Server certificate verify failed\" {
                puts \"❌ Certificate verification failed\"
                exit 1
            }
            \"svrhello status was\" {
                puts \"❌ Server rejected authentication\"
                exit 1
            }
            timeout {
                puts \"❌ Connection timed out\"
                exit 1
            }
            eof {
                puts \"❌ Connection ended unexpectedly\"
                exit 1
            }
        }
        
        interact
    "
}

# Manual connection for debugging timing issues
vpn_connect_manual() {
    echo "🔐 Manual VPN Connection (for debugging timing)..."
    echo "🌐 Server: $(vpn_get_current_server_name) ($VPN_CURRENT_SERVER)"
    
    if ! _get_credentials; then
        return 1
    fi
    
    # Generate OTP and show it to user
    local otp=$(_generate_otp)
    echo "🔑 Generated OTP: $otp"
    echo "📋 Copy this OTP and use it manually"
    echo "⏰ You have ~30 seconds to use it..."
    echo "🚀 Starting manual connection (will prompt for certificate acceptance)..."
    
    # Start connection - user will enter credentials manually
    sudo env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy -u SOCKS_PROXY -u SOCKS5_PROXY -u socks_proxy -u socks5_proxy openconnect --protocol=fortinet \
                     --user=$VPN_USER \
                     --server=$VPN_CURRENT_SERVER \
                     --no-dtls
}

# Test OTP generation and timing
vpn_test_otp() {
    echo "🧪 Testing OTP Generation & Timing"
    echo "=================================="
    
    if ! _get_credentials; then
        return 1
    fi
    
    echo "🔑 Current system time: $(date)"
    
    for i in {1..5}; do
        local otp=$(_generate_otp)
        local timestamp=$(date "+%H:%M:%S")
        echo "[$timestamp] OTP #$i: $otp"
        
        if [[ $i -lt 5 ]]; then
            echo "⏳ Waiting 5 seconds..."
            sleep 5
        fi
    done
    
    echo ""
    echo "💡 Compare these OTPs with your authenticator app"
    echo "💡 They should match within the same 30-second window"
}

# Discover and test VPN routes
vpn_routes() {
    echo "🗺️  VPN Route Analysis"
    echo "====================="
    
    if ! vpn_status >/dev/null; then
        echo "❌ VPN is not connected"
        return 1
    fi
    
    # Get current routing table for VPN interface
    echo "📋 Active VPN routes:"
    netstat -rn | grep -E "(utun|10\.20\.16)" | head -10
    
    echo ""
    echo "🧪 Testing route connectivity:"
    
    # Extract some key routes from netstat and test them
    local routes=$(netstat -rn | grep "10\.20\.16" | awk '{print $1}' | grep -E "^[0-9]" | head -5)
    
    if [[ -n "$routes" ]]; then
        while IFS= read -r route; do
            # Skip network addresses, try to find host addresses
            if [[ "$route" =~ \.[1-9]$ ]]; then
                echo -n "Testing $route... "
                if ping -c 1 -W 2000 "$route" >/dev/null 2>&1; then
                    echo "✅ Reachable"
                else
                    echo "❌ Unreachable"
                fi
            fi
        done <<< "$routes"
    else
        echo "No specific routes found to test"
    fi
    
    # Test some known internal services
    echo ""
    echo "🎯 Testing known internal services:"
    local internal_services=(
        "172.31.1.1"
        "10.21.233.2" 
        "192.168.16.4"
    )
    
    for service in "${internal_services[@]}"; do
        echo -n "Testing $service... "
        if ping -c 1 -W 2000 "$service" >/dev/null 2>&1; then
            echo "✅ Reachable"
        else
            echo "❌ Unreachable"
        fi
    done
}

# Check credential status
vpn_check_credentials() {
    echo "🔍 VPN Credential Status"
    echo "========================"
    
    # Check VPN password
    if security find-generic-password -a "$VPN_USER" -s "$KEYCHAIN_VPN_SERVICE" >/dev/null 2>&1; then
        echo "✅ VPN Password: Found in keychain"
    else
        echo "❌ VPN Password: Not found in keychain"
    fi
    
    # Check TOTP secret
    if security find-generic-password -a "$KEYCHAIN_TOTP_ACCOUNT" -s "$KEYCHAIN_TOTP_SERVICE" >/dev/null 2>&1; then
        echo "✅ TOTP Secret: Found in keychain"
    else
        echo "❌ TOTP Secret: Not found in keychain"
    fi
    
    # Test credential retrieval
    echo ""
    echo "🧪 Testing credential retrieval..."
    
    if _get_credentials >/dev/null 2>&1; then
        local test_otp=$(_generate_otp)
        echo "✅ Credential retrieval: Working"
        echo "🔑 Test OTP generated: $test_otp"
        echo "📱 Compare this with your authenticator app"
        
        # Clean up
        unset VPN_PASSWORD VPN_TOTP_SECRET
    else
        echo "❌ Credential retrieval: Failed"
        echo "💡 Run 'vpn_setup' to fix credential issues"
    fi
}

# Quick credential test (no setup)
vpn_test_credentials() {
    echo "🔑 Quick Credential Test"
    echo "======================="
    
    if _get_credentials >/dev/null 2>&1; then
        local test_otp=$(_generate_otp)
        echo "✅ Credentials are working"
        echo "🔑 Current OTP: $test_otp"
        echo "📱 This should match your authenticator app"
        
        # Clean up
        unset VPN_PASSWORD VPN_TOTP_SECRET
        return 0
    else
        echo "❌ Credentials not accessible"
        echo "💡 Run 'vpn_setup' to configure credentials"
        return 1
    fi
}

# Synchronize system time (helps with OTP timing)
vpn_sync_time() {
    echo "🕐 Synchronizing system time..."
    
    sudo sntp -sS time.apple.com && {
        echo "✅ Time synchronized"
        echo "🕐 Current time: $(date)"
    } || {
        echo "❌ Failed to sync time"
        return 1
    }
}

# Get current server certificate (for troubleshooting)
vpn_check_cert() {
    echo "🔍 Checking server certificate fingerprints..."
    echo "🌐 Server: $(vpn_get_current_server_name) ($VPN_CURRENT_SERVER)"
    echo "=============================================="
    
    local server_host=$(echo $VPN_CURRENT_SERVER | cut -d: -f1)
    local server_port=$(echo $VPN_CURRENT_SERVER | cut -d: -f2)
    
    # Method 1: SHA256 fingerprint (hex format)
    echo "📋 SHA256 Hex Format:"
    timeout 10 openssl s_client -connect $server_host:$server_port -servername $server_host < /dev/null 2>/dev/null | \
    openssl x509 -fingerprint -sha256 -noout 2>/dev/null | \
    sed 's/SHA256 Fingerprint=//' | tr -d ':' | tr '[:upper:]' '[:lower:]'
    
    # Method 2: Get pin-sha256 format
    echo ""
    echo "📋 Pin-SHA256 Format:"
    timeout 10 openssl s_client -connect $server_host:$server_port -servername $server_host < /dev/null 2>/dev/null | \
    openssl x509 -pubkey -noout 2>/dev/null | \
    openssl pkey -pubin -outform DER 2>/dev/null | \
    openssl dgst -sha256 -binary | \
    base64
    
    # Method 3: Test what openconnect actually sees
    echo ""
    echo "📋 OpenConnect Certificate Test:"
    echo "Running quick openconnect test to see certificate info..."
    
    timeout 10 sudo env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy -u SOCKS_PROXY -u SOCKS5_PROXY -u socks_proxy -u socks5_proxy openconnect --protocol=fortinet \
                                --user=$VPN_USER \
                                --server=$VPN_CURRENT_SERVER \
                                --authenticate 2>&1 | \
    grep -E "(pin-sha256|fingerprint|certificate)" || echo "No certificate info captured"
    
    echo ""
    echo "💡 Use one of these formats with --servercert= in your connection"
    echo "💡 Or the connection will auto-discover the correct format"
}

# Auto-reconnect with monitoring
vpn_monitor() {
    local check_interval=${1:-30}  # Default: check every 30 seconds
    
    echo "👁️  Starting VPN monitor (checking every ${check_interval}s)"
    echo "📝 Logs: $VPN_LOGFILE"
    echo "🛑 Press Ctrl+C to stop monitoring"
    
    _log "VPN monitor started (interval: ${check_interval}s)"
    
    while true; do
        if ! vpn_status >/dev/null 2>&1; then
            echo "⚠️  VPN disconnected! Attempting reconnection..."
            _log "VPN disconnection detected, attempting reconnect"
            _notify "VPN Disconnected" "Attempting automatic reconnection..."
            
            if vpn_connect; then
                _log "Auto-reconnection successful"
                _notify "VPN Reconnected" "Automatic reconnection successful"
            else
                _log "Auto-reconnection failed"
                _notify "VPN Reconnection Failed" "Manual intervention may be required"
                echo "❌ Reconnection failed. Will retry in ${check_interval} seconds..."
            fi
        else
            # Check health periodically (every 5th check)
            if (( $(date +%s) % (check_interval * 5) == 0 )); then
                if ! vpn_health >/dev/null 2>&1; then
                    echo "⚠️  VPN health check failed, forcing reconnection..."
                    vpn_disconnect
                    sleep 2
                    vpn_connect
                fi
            fi
        fi
        
        sleep "$check_interval"
    done
}

# Setup credentials (one-time setup)
vpn_setup() {
    echo "🔧 VPN Credential Setup"
    echo "======================"
    
    echo "📝 This will securely store your VPN credentials in macOS Keychain"
    echo ""
    
    # Store VPN password (update if exists, create if new)
    echo "🔐 Enter your VPN password:"
    if security find-generic-password -a "$VPN_USER" -s "$KEYCHAIN_VPN_SERVICE" >/dev/null 2>&1; then
        echo "🔄 Updating existing VPN password..."
        security delete-generic-password -a "$VPN_USER" -s "$KEYCHAIN_VPN_SERVICE" 2>/dev/null
    fi
    
    security add-generic-password -a "$VPN_USER" -s "$KEYCHAIN_VPN_SERVICE" -w || {
        echo "❌ Failed to store VPN password"
        return 1
    }
    
    # Store TOTP secret (update if exists, create if new)
    echo "🔑 Enter your TOTP secret key:"
    if security find-generic-password -a "$KEYCHAIN_TOTP_ACCOUNT" -s "$KEYCHAIN_TOTP_SERVICE" >/dev/null 2>&1; then
        echo "🔄 Updating existing TOTP secret..."
        security delete-generic-password -a "$KEYCHAIN_TOTP_ACCOUNT" -s "$KEYCHAIN_TOTP_SERVICE" 2>/dev/null
    fi
    
    security add-generic-password -a "$KEYCHAIN_TOTP_ACCOUNT" -s "$KEYCHAIN_TOTP_SERVICE" -w || {
        echo "❌ Failed to store TOTP secret"
        return 1
    }
    
    echo "✅ Credentials stored successfully!"
    echo "🧪 Testing credential retrieval..."
    
    if _get_credentials; then
        local test_otp=$(_generate_otp)
        echo "🔑 Test OTP generated: $test_otp"
        echo "🎉 Setup complete! You can now use 'vpn_connect'"
        
        # Clean up exported variables
        unset VPN_PASSWORD VPN_TOTP_SECRET
    else
        echo "❌ Setup verification failed"
        return 1
    fi
}

# Show logs
vpn_logs() {
    local lines=${1:-50}
    
    if [[ -f "$VPN_LOGFILE" ]]; then
        echo "📋 Last $lines VPN log entries:"
        echo "================================"
        tail -n "$lines" "$VPN_LOGFILE"
    else
        echo "📝 No log file found at $VPN_LOGFILE"
    fi
}

# =============================================================================

