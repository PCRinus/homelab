# AdGuard Home

AdGuard Home runs as the network DNS ad blocker for the LAN. UniFi remains the DHCP server; AdGuard only serves DNS and the admin dashboard.

## Service

- Compose file: `adguard/compose.yml`
- Start script: `adguard/start.sh`
- Admin UI: `http://192.168.1.166:3001`
- DNS listener: `192.168.1.166:53`
- Persistent config: `${DOCKER_DATA}/adguard/conf`
- Persistent work data: `${DOCKER_DATA}/adguard/work`

The container command explicitly writes the config into the mounted `conf` directory:

```yaml
--config /opt/adguardhome/conf/AdGuardHome.yaml
--work-dir /opt/adguardhome/work
```

Do not remove those flags. Without them, AdGuard can write config into an ephemeral container path and lose setup on recreation.

## First-Run Setup

Open:

```text
http://192.168.1.166:3001/install.html
```

Use these wizard values:

```text
Admin Web Interface
  Listen interface: All interfaces
  Port: 3001

DNS server
  Listen interface: All interfaces
  Port: 53
```

Ignore the Docker-internal IP shown by the wizard, such as `172.x.x.x`. LAN clients should use `192.168.1.166`.

On the static IP step, continue without changing anything. The server IP is handled outside AdGuard, either by the host network configuration or UniFi reservation.

Create an admin username/password and update the homelab env values used by Homepage:

```dotenv
ADGUARD_USER=...
ADGUARD_PASS=...
HOMEPAGE_VAR_ADGUARD_USER=...
HOMEPAGE_VAR_ADGUARD_PASS=...
```

## Recommended Settings

In `Settings -> DNS settings`:

```text
Upstream DNS servers:
  https://dns10.quad9.net/dns-query

Bootstrap DNS servers:
  9.9.9.10
  149.112.112.10
  2620:fe::10
  2620:fe::fe:10

Rate limit: 0
DNSSEC: enabled
EDNS Client Subnet: disabled
```

`Rate limit: 0` is appropriate while AdGuard is LAN-only. If AdGuard is ever exposed as a public resolver, revisit this immediately.

In `Filters -> DNS blocklists`, keep the list set conservative:

```text
AdGuard DNS filter
OISD Big
Dandelion Sprout's Anti-Malware List
```

Start with a small number of high-quality lists. More lists usually mean more false positives and harder debugging.

In `Settings -> General settings`:

```text
Query log: enabled
Query log retention: 7 days
Statistics: enabled
Statistics retention: 30 days
```

Keep AdGuard DHCP disabled. UniFi should remain the only DHCP server.

## UniFi Cutover

After AdGuard is configured and DNS blocking is verified, set the LAN DHCP DNS server in UniFi:

```text
Settings -> Networks -> Default/LAN -> DHCP
Auto DNS Server: disabled
DNS Server: 192.168.1.166
```

Do not add `1.1.1.1`, `8.8.8.8`, or any other secondary DNS server in UniFi. Many clients will use secondary resolvers opportunistically, bypassing AdGuard.

Leave these settings alone:

```text
DHCP Mode: DHCP Server
Auto Default Gateway: enabled
AdGuard DHCP: disabled
```

After saving, renew DHCP on clients by reconnecting Wi-Fi or waiting for the lease to renew.

## Verification

From any machine on the LAN:

```bash
dig @192.168.1.166 google.com
dig @192.168.1.166 doubleclick.net
```

Expected:

```text
google.com resolves to real IP addresses
doubleclick.net resolves to 0.0.0.0
```

On macOS, check DHCP-provided DNS:

```bash
scutil --dns | grep nameserver
```

If Tailscale MagicDNS is enabled, macOS may show `100.100.100.100` first. For clean AdGuard tests, use explicit `dig @192.168.1.166 ...` commands and confirm queries appear in the AdGuard query log.

Gatus has two AdGuard checks:

- `AdGuard / Dashboard`: verifies the web UI is reachable.
- `AdGuard / DNS Blocking`: queries `doubleclick.net` through AdGuard and expects `0.0.0.0`.

## Reset

Before resetting, temporarily change UniFi DHCP DNS back to automatic DNS or public resolvers so clients do not depend on AdGuard during the reset.

Then on the server:

```bash
cd /home/mircea/homeserver/adguard
docker compose --env-file ../.env down

TS="$(date +%Y%m%d-%H%M%S)"
docker run --rm -v "$DOCKER_DATA/adguard:/adguard" busybox:1.37 sh -c \
  "set -e; for d in conf work; do if [ -e /adguard/\$d ]; then mv /adguard/\$d /adguard/\${d}.backup.$TS; fi; done"

./start.sh
```

The reset keeps backups next to the fresh data directories:

```text
${DOCKER_DATA}/adguard/conf.backup.YYYYMMDD-HHMMSS
${DOCKER_DATA}/adguard/work.backup.YYYYMMDD-HHMMSS
```

To roll back, stop AdGuard, move the fresh `conf` and `work` aside, restore the backup directory names, and start AdGuard again.
