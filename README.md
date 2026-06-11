# Snapp VPN (OpenConnect + Fortinet)

Shell toolkit for connecting to Snapp FortiGate VPN from macOS with:

- Automatic password + TOTP via `expect` and Keychain
- Certificate pin caching
- Multi-site switching (`site1`, `site2`, `site3`)
- Stale route cleanup (common macOS issue after disconnect)
- Auto-reconnect on unexpected tunnel drop

## Requirements

- macOS
- `zsh`
- [OpenConnect](https://www.infradead.org/openconnect/) (`brew install openconnect`)
- `expect` (`brew install expect`)
- `oathtool` (`brew install oath-toolkit`)

## Install

```bash
git clone <this-repo> ~/dev/scripts/snapp-vpn
cd ~/dev/scripts/snapp-vpn
./install.sh
```

Edit `~/.config/snapp-vpn/config` and set `SNAPP_VPN_USER`.

```bash
source ~/.zshrc
vpn_setup   # one-time: store VPN password + TOTP secret in Keychain
vpn         # connect
```

## Common commands

| Command | Description |
|---------|-------------|
| `vpn` | Connect (smart: skip if already up) |
| `vpnoff` | Disconnect and clean stale routes |
| `vpnswitch site2` | Switch VPN gateway |
| `vpnservers` | List servers |
| `vpns` | Status |
| `vpndiag` | Network diagnostics |
| `vpn_help` | Full help |

## Configuration

User-specific settings live in `~/.config/snapp-vpn/config` (not in git).

See `config.example` for all options: servers, health-check endpoints, keychain service names.

Runtime state (not in repo):

- `~/.vpn_config` — last selected server
- `~/.vpn_servercerts` — cached TLS pins
- `~/.vpn_connection.log` — connection log

## DNS (DC team note)

If you use **OpenConnect**, internal DNS (`10.21.232.232`, `10.22.232.232`) is pushed automatically when the tunnel is up. No extra client config is required.

## Troubleshooting

**`Can't assign requested address`**

Stale host routes from a previous session. Run:

```bash
vpnoff
vpn
```

Or manually:

```bash
sudo route delete -host 77.238.120.132
sudo route delete -host 79.175.182.85
```

**`Failed to complete authentication` right after connect errors**

Usually a network/routing failure, not wrong password. Run `vpndiag` and `vpnnettest`.

## Project layout

```
snapp-vpn.zsh          # entrypoint (source this)
lib/
  config.zsh           # paths, config load, route/cert helpers
  servers.zsh          # server list / switch
  credentials.zsh      # Keychain password + TOTP
  core.zsh             # shared helpers
  monitor.zsh          # status, health, diagnose
  connect.zsh          # connect / disconnect / reconnect
  advanced.zsh         # background, manual, monitor, setup
  aliases.zsh          # shortcuts + help
config.example
install.sh
```

## License

Internal Snapp tooling — distribute only within your organization.
