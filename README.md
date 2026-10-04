# Windscribe IPs for MikroTik (Pre-generated RSC)

This repository provides a ready-to-import RouterOS `.rsc` file containing Windscribe VPN IP addresses.

The IP lists are automatically fetched from [tn3w/Windscribe-IPs](https://github.com/tn3w/Windscribe-IPs) every 6 hours via GitHub Actions and converted to a MikroTik-compatible format.

## Generated File

**`windscribe.rsc`** — A RouterOS importable script that creates two address lists:

| Address List | Source | Description |
|--------------|--------|-------------|
| `windscribe-servers` | `windscribe_ips.txt` | VPN server IPs (~378 IPs) |
| `windscribe-entry` | `windscribe_entry_ips.txt` | Entry/portal IPs (~1089 IPs) |

## MikroTik Usage

### Download and Import

```routeros
# 1. Fetch the RSC file from GitHub
/tool fetch \
    url="https://raw.githubusercontent.com/honarkar98/windscribe-mikrotik/main/windscribe.rsc" \
    dst-path=windscribe.rsc \
    mode=https

# 2. Remove old entries (optional, for clean slate)
/ip firewall address-list remove [find list="windscribe-servers"]
/ip firewall address-list remove [find list="windscribe-entry"]

# 3. Import the new list
/import file-name=windscribe.rsc

# 4. Clean up the downloaded file
/file remove windscribe.rsc
```

Replace `YOUR_USER` with your GitHub username/organization.

### Automate Updates (Scheduler)

Run the update daily at 3 AM:

```routeros
/system/scheduler/add name="windscribe-update-daily" \
    on-event="/tool fetch url=\"https://raw.githubusercontent.com/honarkar98/windscribe-mikrotik/main/windscribe.rsc\" dst-path=windscribe.rsc mode=https;\
    /ip firewall address-list remove [find list=\"windscribe-servers\"];\
    /ip firewall address-list remove [find list=\"windscribe-entry\"];\
    /import file-name=windscribe.rsc;\
    /file remove windscribe.rsc" \
    interval=1d start-time=03:00:00
```

## Firewall Examples

### Block Windscribe VPN Access

```routeros
# Block all Windscribe server IPs (prevent VPN connections TO your network)
/ip/firewall/filter
add chain=forward src-address-list=windscribe-servers action=drop \
    comment="Block Windscribe VPN servers" place-before=0

# Block Windscribe entry IPs (prevent clients FROM connecting to Windscribe)
/ip/firewall/filter
add chain=forward dst-address-list=windscribe-entry action=drop \
    comment="Block Windscribe VPN entry points" place-before=0
```

### Route Windscribe Traffic via Specific Gateway

```routeros
# Mark routing for Windscribe IPs
/ip/firewall/mangle
add chain=prerouting src-address-list=windscribe-servers \
    action=mark-routing new-routing-mark=via-wg passthrough=yes

# Route marked traffic via WireGuard/VPN
/ip/route
add dst-address=0.0.0.0/0 gateway=wireguard1 routing-mark=via-wg
```

### QoS/Throttle Windscribe Traffic

```routeros
/queue/tree
add name="windscribe-download" parent=global queue=default \
    target=windscribe-servers max-limit=5M

add name="windscribe-upload" parent=global queue=default \
    target=windscribe-entry max-limit=2M
```

## How It Works

```
┌─────────────────────┐     HTTPS      ┌──────────────────┐
│ tn3w/Windscribe-IPs │ ─────────────► │  GitHub Action   │
│  (source repo)      │  (every 6 hrs) │  (generate.py)   │
└─────────────────────┘                └────────┬─────────┘
                                                │
                                                │ generate
                                                ▼
                                         ┌──────────────────┐
                                         │  windscribe.rsc  │
                                         │  (committed)     │
                                         └────────┬─────────┘
                                                  │
                                                  │ GitHub Raw HTTPS
                                                  ▼
                                         ┌──────────────────┐
                                         │     MikroTik     │
                                         │  /tool fetch     │
                                         │  /import         │
                                         └──────────────────┘
```

- **No secrets or API keys required** — everything is public
- **MikroTik downloads directly from GitHub** — no intermediate server
- **GitHub Actions bot commits changes** — only when the IP list actually changes
- **Validation prevents corruption** — if the source is unavailable or returns too few IPs, the workflow fails and the previous valid file is preserved

## Requirements

- RouterOS v7.x (tested on 7.10+)
- Internet access for `/tool fetch`
- HTTPS support (built-in on v7.x)

## Source Data

Data sourced from: https://github.com/tn3w/Windscribe-IPs
- Automatically updated via GitHub Actions
- Apache-2.0 License
- No API keys required

## License

This repository is provided as-is. The IP data belongs to the original source (tn3w/Windscribe-IPs).