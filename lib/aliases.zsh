# =============================================================================

# Short aliases for common operations
alias vpn='vpn_smart_connect'
alias vpnbg='vpn_connect_background'
alias vpnoff='vpn_disconnect'
alias vpns='vpn_status'
alias vpnh='vpn_health'
alias vpnm='vpn_monitor'
alias vpnl='vpn_logs'

# Server management aliases
alias vpnservers='vpn_list_servers'
alias vpnswitch='vpn_switch'

# Credential management aliases  
alias vpnpassword='vpn_update_password'
alias vpnotp='vpn_update_otp'
alias vpncreds='vpn_update_credentials'
alias vpncheck='vpn_check_credentials'
alias vpntestcreds='vpn_test_credentials'

# Debugging aliases
alias vpnmanual='vpn_connect_manual'
alias vpntest='vpn_test_otp'
alias vpntime='vpn_sync_time'
alias vpncert='vpn_check_cert'
alias vpnroutes='vpn_routes'
alias vpndiag='vpn_diagnose'
alias vpnnettest='vpn_nettest'

# =============================================================================
# HELP FUNCTION
# =============================================================================

vpn_help() {
    cat << 'EOF'
🔐 SNAPP VPN TOOLKIT - ENHANCED
==============================

SETUP (run once):
  vpn_setup              - Store credentials securely in keychain

CONNECTION:
  vpn_connect           - Connect to VPN (interactive mode)
  vpn_connect_background- Connect to VPN (background mode)
  vpn_smart_connect     - Connect only if not already connected
  vpn_disconnect        - Gracefully disconnect VPN
  vpn                   - Alias for vpn_smart_connect
  vpnbg                 - Alias for vpn_connect_background

SERVER MANAGEMENT:
  vpn_list_servers      - Show available servers (site1, site2, site3)
  vpn_switch <server>   - Switch between site1, site2, and site3
  vpnservers            - Alias for vpn_list_servers
  vpnswitch             - Alias for vpn_switch

CREDENTIAL MANAGEMENT:
  vpn_update_password   - Update VPN password in keychain
  vpn_update_otp        - Update OTP secret in keychain
  vpn_update_credentials- Update both password and OTP
  vpn_check_credentials - Check credential status in keychain
  vpn_test_credentials  - Quick test of current credentials
  vpnpassword           - Alias for vpn_update_password
  vpnotp                - Alias for vpn_update_otp
  vpncreds              - Alias for vpn_update_credentials
  vpncheck              - Alias for vpn_check_credentials
  vpntestcreds          - Alias for vpn_test_credentials

MONITORING:
  vpn_status            - Check connection status
  vpn_health            - Detailed health diagnostics
  vpn_monitor [secs]    - Auto-reconnect monitor (default: 30s)
  vpn_logs [lines]      - Show recent log entries (default: 50)

DEBUGGING & TROUBLESHOOTING:
  vpn_connect_manual    - Manual connection for timing debugging
  vpn_test_otp          - Test OTP generation and timing
  vpn_sync_time         - Synchronize system time (helps with OTP)
  vpn_check_cert        - Check server certificate fingerprint
  vpn_routes            - Analyze VPN routes and test connectivity
  vpn_diagnose          - Comprehensive network diagnostics
  vpn_nettest           - Quick network connectivity test

ALIASES:
  vpn      -> vpn_smart_connect
  vpnbg    -> vpn_connect_background
  vpnoff   -> vpn_disconnect  
  vpns     -> vpn_status
  vpnh     -> vpn_health
  vpnm     -> vpn_monitor
  vpnl     -> vpn_logs
  
  SERVER ALIASES:
  vpnservers -> vpn_list_servers
  vpnswitch  -> vpn_switch
  
  CREDENTIAL ALIASES:
  vpnpassword -> vpn_update_password
  vpnotp      -> vpn_update_otp
  vpncreds    -> vpn_update_credentials
  vpncheck    -> vpn_check_credentials
  vpntestcreds-> vpn_test_credentials

EXAMPLES:
  vpn_setup                    # One-time credential setup
  vpn                          # Connect to current server
  vpnbg                        # Connect in background (persistent)
  
  vpnswitch site2              # Switch to site2.snapp.cab
  vpnswitch site1              # Switch back to site1.snapp.cab
  vpnswitch site3              # Switch to site3.dc.snappcloud.io
  vpnservers                   # Show available servers
  
  vpnpassword                  # Update VPN password
  vpnotp                       # Update OTP secret
  vpncreds                     # Update both credentials
  vpncheck                     # Check credential status
  vpntestcreds                 # Quick credential test
  
  vpn_test_otp                 # Debug OTP timing issues
  vpn_sync_time                # Fix system time if OTP fails
  vpn_diagnose                 # Full network diagnostics
  vpn_nettest                  # Quick connectivity test
  vpnm 60                      # Monitor with 60-second intervals
  vpnl 100                     # Show last 100 log entries

📝 Logs are stored in: ~/.vpn_connection.log
🔧 Troubleshooting: Run vpn_diagnose for connection issues
💡 Use vpnbg for persistent background connections that won't timeout
🌐 Current server: $(vpn_get_current_server_name) ($(echo $VPN_CURRENT_SERVER))
EOF
}

