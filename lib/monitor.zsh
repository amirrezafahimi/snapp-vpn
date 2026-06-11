# Status and monitoring
# =============================================================================

# Comprehensive network diagnostics for VPN troubleshooting
vpn_diagnose() {
    echo "🩺 VPN Network Diagnostics"
    echo "=========================="
    echo "🌐 Current server: $(vpn_get_current_server_name) ($VPN_CURRENT_SERVER)"
    echo ""
    
    local server_host=$(echo $VPN_CURRENT_SERVER | cut -d: -f1)
    local server_port=$(echo $VPN_CURRENT_SERVER | cut -d: -f2)
    
    # Test 1: Basic connectivity
    echo "🔍 Test 1: Basic Internet Connectivity"
    if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
        echo "✅ Internet connectivity: Working"
    else
        echo "❌ Internet connectivity: Failed"
        echo "💡 Check your internet connection first"
        return 1
    fi
    
    # Test 2: DNS Resolution
    echo ""
    echo "🔍 Test 2: DNS Resolution"
    local resolved_ip=$(nslookup $server_host 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')
    if [[ -n "$resolved_ip" ]]; then
        echo "✅ DNS resolution: $server_host → $resolved_ip"
    else
        echo "❌ DNS resolution: Failed for $server_host"
        echo "💡 Try: sudo dscacheutil -flushcache"
        return 1
    fi
    
    # Test 3: Ping test
    echo ""
    echo "🔍 Test 3: Server Reachability"
    if ping -c 3 $server_host >/dev/null 2>&1; then
        echo "✅ Ping to $server_host: Working"
    else
        echo "❌ Ping to $server_host: Failed"
        echo "💡 Server might be down or blocking ping"
    fi
    
    # Test 4: Port connectivity
    echo ""
    echo "🔍 Test 4: Port Connectivity"
    if command -v nc >/dev/null; then
        if timeout 5 nc -z $server_host $server_port 2>/dev/null; then
            echo "✅ Port $server_port on $server_host: Open"
        else
            echo "❌ Port $server_port on $server_host: Closed/Filtered"
            echo "💡 Port might be blocked by firewall or server is down"
        fi
    else
        echo "⚠️  netcat (nc) not available, skipping port test"
        echo "💡 Install with: brew install netcat"
    fi
    
    # Test 5: SSL/HTTPS test
    echo ""
    echo "🔍 Test 5: HTTPS Connectivity"
    if timeout 10 openssl s_client -connect $server_host:$server_port -quiet < /dev/null >/dev/null 2>&1; then
        echo "✅ HTTPS connection to $server_host:$server_port: Working"
    else
        echo "❌ HTTPS connection to $server_host:$server_port: Failed"
        echo "💡 SSL/TLS connection issues"
    fi
    
    # Test 6: Network configuration
    echo ""
    echo "🔍 Test 6: Network Configuration"
    echo "📋 Active network interface:"
    route get default 2>/dev/null | grep interface | head -1
    
    echo "📋 Default gateway:"
    route get default 2>/dev/null | grep gateway | head -1
    
    # Test 7: Proxy detection
    echo ""
    echo "🔍 Test 7: Proxy Configuration"
    local http_proxy=$(networksetup -getwebproxy Wi-Fi 2>/dev/null | grep "Enabled: Yes")
    local https_proxy=$(networksetup -getsecurewebproxy Wi-Fi 2>/dev/null | grep "Enabled: Yes")
    
    if [[ -n "$http_proxy" || -n "$https_proxy" ]]; then
        echo "⚠️  Proxy detected - this might interfere with VPN"
        networksetup -getwebproxy Wi-Fi
        networksetup -getsecurewebproxy Wi-Fi
    else
        echo "✅ No proxy detected"
    fi
    
    # Test 8: Try all configured servers
    echo ""
    echo "🔍 Test 8: Testing All Configured Servers"
    for site in ${VPN_SERVER_ORDER[@]}; do
        local test_server="${VPN_SERVERS[$site]}"
        local test_host=$(echo $test_server | cut -d: -f1)
        local test_port=$(echo $test_server | cut -d: -f2)
        
        echo -n "Testing $site ($test_host:$test_port)... "
        if timeout 5 nc -z $test_host $test_port 2>/dev/null; then
            echo "✅ Reachable"
        else
            echo "❌ Unreachable"
        fi
    done
    
    echo ""
    echo "🎯 Diagnostic Summary:"
    echo "====================="
    echo "💡 If all tests pass: Try 'vpn_connect_manual' for detailed debugging"
    echo "💡 If DNS fails: Run 'sudo dscacheutil -flushcache'"
    echo "💡 If port tests fail: Check firewall or try different network"
    echo "💡 If proxy detected: Consider disabling proxy temporarily"
    echo "💡 If everything fails: Try 'vpnswitch' to other server"
}

# Quick network test
vpn_nettest() {
    echo "🌐 Quick Network Test"
    echo "===================="
    
    local server_host=$(echo $VPN_CURRENT_SERVER | cut -d: -f1)
    local server_port=$(echo $VPN_CURRENT_SERVER | cut -d: -f2)
    
    echo -n "🔍 Testing $server_host:$server_port... "
    if timeout 5 nc -z $server_host $server_port 2>/dev/null; then
        echo "✅ Reachable"
        echo "💡 Network looks good, try connecting"
        return 0
    else
        echo "❌ Unreachable"
        echo "💡 Run 'vpn_diagnose' for detailed analysis"
        return 1
    fi
}

# Check if VPN is currently connected
vpn_status() {
    local server_host="${VPN_CURRENT_SERVER%%:*}"
    local openconnect_pid=$(pgrep -f "openconnect.*${server_host}" 2>/dev/null)
    
    if [[ -n "$openconnect_pid" ]]; then
        echo "🟢 VPN Status: CONNECTED"
        echo "   Process ID: $openconnect_pid"
        
        # Get VPN interface info
        local vpn_ip=$(ifconfig | grep -A 1 "utun" | grep "inet " | head -1 | awk '{print $2}')
        if [[ -n "$vpn_ip" ]]; then
            echo "   VPN IP: $vpn_ip"
            
            # Test VPN gateway connectivity
            local gateway="${vpn_ip%.*}.1"
            if ping -c 1 -W 2000 "$gateway" >/dev/null 2>&1; then
                echo "   VPN Gateway: ✅ Reachable ($gateway)"
            else
                # Try a known internal server instead
                if ping -c 1 -W 2000 172.31.1.1 >/dev/null 2>&1; then
                    echo "   Internal Network: ✅ Reachable"
                else
                    echo "   Internal Network: ⚠️  Not reachable"
                fi
            fi
        fi
        
        return 0
    else
        echo "🔴 VPN Status: DISCONNECTED"
        return 1
    fi
}

# Check VPN health with detailed diagnostics
vpn_health() {
    echo "🏥 VPN Health Check"
    echo "==================="
    
    if ! vpn_status >/dev/null; then
        echo "❌ VPN is not connected"
        return 1
    fi
    
    # Test VPN gateway (derived from VPN IP)
    local vpn_ip=$(ifconfig | grep -A 1 "utun" | grep "inet " | head -1 | awk '{print $2}')
    if [[ -n "$vpn_ip" ]]; then
        local gateway="${vpn_ip%.*}.1"  # e.g., 10.20.16.1 from 10.20.16.162
        echo "🌐 Testing VPN gateway: $gateway"
        if ping -c 1 -W 2000 "$gateway" >/dev/null 2>&1; then
            echo "✅ VPN Gateway ($gateway) - Reachable"
        else
            echo "❌ VPN Gateway ($gateway) - Unreachable"
        fi
    fi
    
    # Test real internal endpoints from VPN routes
    local test_endpoints=(
        "172.31.1.1"        # Actual routed host
        "10.21.233.2"       # Actual routed host
        "192.168.16.4"      # Actual routed host
        "172.31.4.254"      # Actual routed host
        "172.30.90.2"       # Actual routed host
    )
    
    echo ""
    echo "🎯 Testing actual internal servers:"
    local success_count=0
    for endpoint in "${test_endpoints[@]}"; do
        if ping -c 1 -W 2000 "$endpoint" >/dev/null 2>&1; then
            echo "✅ $endpoint - Reachable"
            ((success_count++))
        else
            echo "❌ $endpoint - Unreachable"
        fi
    done
    
    echo ""
    echo "📊 Health Score: $success_count/${#test_endpoints[@]} servers reachable"
    
    # Test DNS resolution through VPN
    echo ""
    echo "🌐 Testing DNS resolution:"
    if nslookup google.com >/dev/null 2>&1; then
        echo "✅ DNS Resolution - Working"
    else
        echo "❌ DNS Resolution - Failed"
    fi
    
    # Test external connectivity through VPN
    echo ""
    echo "🌍 Testing external connectivity:"
    if curl -s --max-time 5 --connect-timeout 3 http://httpbin.org/ip >/dev/null 2>&1; then
        echo "✅ External Internet - Reachable through VPN"
    else
        echo "❌ External Internet - Not reachable"
    fi
    
    if [[ $success_count -eq 0 ]]; then
        echo ""
        echo "⚠️  VPN is connected but internal servers are unreachable"
        echo "💡 This might be normal if those servers are down or restricted"
        return 2
    fi
    
    return 0
}

# =============================================================================

