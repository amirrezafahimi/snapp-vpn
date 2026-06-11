# Credential management (macOS Keychain)

# Update VPN password
vpn_update_password() {
    echo "🔐 Update VPN Password"
    echo "====================="
    echo "💡 This will update your stored VPN password in macOS Keychain"
    echo ""
    
    # Remove old password
    security delete-generic-password -a "$VPN_USER" -s "$KEYCHAIN_VPN_SERVICE" 2>/dev/null
    
    # Add new password
    echo "🔑 Enter your new VPN password:"
    security add-generic-password -a "$VPN_USER" -s "$KEYCHAIN_VPN_SERVICE" -w || {
        echo "❌ Failed to store new password"
        return 1
    }
    
    echo "✅ VPN password updated successfully!"
    echo "🧪 Testing new password retrieval..."
    
    if _get_credentials >/dev/null 2>&1; then
        echo "✅ Password retrieval test passed"
        _log "VPN password updated"
    else
        echo "❌ Password retrieval test failed"
        return 1
    fi
}

# Update OTP secret
vpn_update_otp() {
    echo "🔑 Update OTP Secret"
    echo "==================="
    echo "💡 This will update your TOTP secret key in macOS Keychain"
    echo "💡 Get this from your authenticator app or IT department"
    echo ""
    
    # Remove old TOTP secret
    security delete-generic-password -a "$KEYCHAIN_TOTP_ACCOUNT" -s "$KEYCHAIN_TOTP_SERVICE" 2>/dev/null
    
    # Add new TOTP secret
    echo "🔐 Enter your new TOTP secret key:"
    security add-generic-password -a "$KEYCHAIN_TOTP_ACCOUNT" -s "$KEYCHAIN_TOTP_SERVICE" -w || {
        echo "❌ Failed to store new TOTP secret"
        return 1
    }
    
    echo "✅ TOTP secret updated successfully!"
    echo "🧪 Testing new OTP generation..."
    
    if _get_credentials >/dev/null 2>&1; then
        local test_otp=$(_generate_otp)
        echo "🔑 Test OTP generated: $test_otp"
        echo "📱 Compare this with your authenticator app"
        echo "✅ If they match, the update was successful!"
        _log "TOTP secret updated"
    else
        echo "❌ OTP generation test failed"
        return 1
    fi
}

# Update both password and OTP (complete credential refresh)
vpn_update_credentials() {
    echo "🔧 Complete Credential Update"
    echo "============================="
    echo "💡 This will update both your VPN password and OTP secret"
    echo ""
    
    read -p "🔐 Update VPN password? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        vpn_update_password || return 1
        echo ""
    fi
    
    read -p "🔑 Update OTP secret? (y/N): " -n 1 -r  
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        vpn_update_otp || return 1
        echo ""
    fi
    
    echo "🎉 Credential update complete!"
    echo "💡 Test the connection with 'vpn' to verify everything works"
}
