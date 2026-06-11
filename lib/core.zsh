# Core helpers
# =============================================================================

# Get credentials from keychain
_get_credentials() {
    local password=$(security find-generic-password -a "$VPN_USER" -s "$KEYCHAIN_VPN_SERVICE" -w 2>/dev/null)
    local totp_secret=$(security find-generic-password -a "$KEYCHAIN_TOTP_ACCOUNT" -s "$KEYCHAIN_TOTP_SERVICE" -w 2>/dev/null)
    
    if [[ -z "$password" || -z "$totp_secret" ]]; then
        echo "❌ Error: Credentials not found in keychain"
        echo "💡 Run 'vpn_setup' first to store credentials securely"
        return 1
    fi
    
    # Export for use in calling function
    export VPN_PASSWORD="$password"
    export VPN_TOTP_SECRET="$totp_secret"
    return 0
}

# Generate current OTP
_generate_otp() {
    if [[ -z "$VPN_TOTP_SECRET" ]]; then
        echo "❌ TOTP secret not available"
        return 1
    fi
    oathtool -b --totp "$VPN_TOTP_SECRET"
}

# Log with timestamp
_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$VPN_LOGFILE"
}

# Send macOS notification
_notify() {
    local title="$1"
    local message="$2"
    osascript -e "display notification \"$message\" with title \"$title\""
}

# =============================================================================

