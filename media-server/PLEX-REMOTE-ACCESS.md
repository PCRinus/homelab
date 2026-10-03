# Plex Remote Access via Pangolin

The home connection is behind CGNAT, so Plex's built-in Remote Access (port forwarding) cannot work. Remote clients reach Plex through a Pangolin VPS instead, and Plex Relay is disabled so clients never fall back to its bandwidth cap.

## How Clients Connect

```
Plex client ──HTTPS──▶ stream.home-server.me:443 (VPS 194.102.107.75)
                       Traefik (Let's Encrypt TLS) ─▶ Gerbil (WireGuard)
                              │
                              ▼  outbound WireGuard tunnel
                       newt container (homeserver, media-net) ─▶ http://plex:32400
```

| Piece | Where it is defined |
|-------|---------------------|
| `stream.home-server.me` A record (DNS-only, not proxied) | `cloudflare-tunnel/dns.tf` |
| Pangolin, Gerbil, Traefik on the VPS | `vps/compose.yml` (config lives on the VPS under `/opt/pangolin/config`) |
| `newt` tunnel connector | `media-server/compose.yml` |

Requests from remote clients arrive at Plex from the `newt` container's address on `media-net` (e.g. `172.18.0.24`) with `Host: stream.home-server.me`.

`plex.home-server.me` (Cloudflare Tunnel) still exists for browser access, but it is not advertised to Plex clients. Cloudflare's terms don't allow streaming video through the tunnel, so it shouldn't carry playback.

### Connection types and their limits

| Connection | Limit |
|------------|-------|
| Direct via `stream.home-server.me` | None from Plex: original quality, direct play |
| Plex Relay (disabled here) | 2 Mbps with Plex Pass on the server, 1 Mbps without |

Shared users don't need their own Plex Pass. The server owner's Plex Pass covers remote streaming for everyone the server is shared with.

## Plex Settings

Configure in Plex Web → **Settings** → (server) **Network** → **Show Advanced**:

| Setting | Value | Why |
|---------|-------|-----|
| Custom server access URLs | `https://stream.home-server.me:443` | Plex.tv advertises this URL to clients. The `:443` suffix is required (it fixes iOS downloads and other client quirks). |
| LAN Networks | `192.168.1.0/24,100.64.0.0/10` | Home LAN and Tailscale/CGNAT addresses count as local (no remote bandwidth rules) |
| Enable Relay | **Off** | Without this, clients that briefly can't reach `stream.` (e.g. during a Plex restart) fall back to Relay and stay capped at 2 Mbps until the app reconnects |
| Secure connections | Preferred | TLS is terminated on the VPS |

**Settings → Remote Access** stays disabled. Port mapping cannot work behind CGNAT, and the custom URL above replaces it.

Save, then restart Plex so plex.tv picks up the new connection list:

```bash
cd /home/mircea/homeserver/media-server && docker restart plex
```

Clients refresh their connection list on app restart, or by signing out and back in.

### Turning off Relay

1. Open Plex Web and select the server in the sidebar
2. **Settings** (wrench icon) → under the server name, **Network**
3. Click **Show Advanced** at the top of the page
4. Uncheck **Enable Relay**
5. **Save Changes**

The trade-off: if the VPS or the newt tunnel is down, remote playback fails instead of degrading to Relay. Gatus monitors `https://stream.home-server.me/identity` (`monitoring/config.yaml`), so that outage is visible.

## Verifying

### What plex.tv advertises to clients

Run this on the homeserver. Expected output: a remote `stream.home-server.me` connection, a Docker-internal local address, and no `RELAY` line once Relay is disabled.

```bash
P="$HOME/docker/plex/config/Library/Application Support/Plex Media Server"
T=$(grep -o 'PlexOnlineToken="[^"]*' "$P/Preferences.xml" | cut -d'"' -f2)
curl -s "https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1" \
  -H "Accept: application/json" -H "X-Plex-Token: $T" -H "X-Plex-Client-Identifier: diag-cli" |
  python3 -c '
import json, sys
for r in json.load(sys.stdin):
    if "server" in r.get("provides", ""):
        for c in r["connections"]:
            print(r["name"], c["uri"], "local" if c["local"] else "remote", "RELAY" if c["relay"] else "")'
```

### Per-session connection type

Tautulli → **Activity** shows each stream's location (LAN/WAN), quality, and whether it is relayed. History stores the same fields per session, so you can review a user's past sessions after the fact.

## Monitoring Stream Quality

Tautulli has a Discord notifier named **Plex quality alert**. It fires on **Playback Start** and **Transcode Decision Change** when:

```
{1} stream_location is wan  AND  ( {2} quality_profile is not Original  OR  {3} relayed is 1 )
```

This catches:
- remote streams that start below original quality (usually the client's quality setting)
- Plex auto-lowering quality mid-stream ("connection too slow" on the TV); this starts a new transcode session, which triggers Transcode Decision Change
- any Relay session

To change it: Tautulli → **Settings → Notification Agents → Plex quality alert**.

### Low quality without Relay is a client setting

Most low-quality remote streams come from the client, not the connection. The app requests a bitrate cap (visible in the Plex log as `maxVideoBitrate=2000&videoQuality=60` for "2 Mbps 720p"). Ask the user to set their app's quality settings to **Original / Maximum**:
- **Remote/Internet streaming quality**
- **Cellular quality** (mobile apps keep a separate, lower setting for mobile data)
- Optionally turn off **Automatically adjust quality**, if their connection can sustain the original bitrate

## Troubleshooting

### A stream shows as relayed

- Check that **Enable Relay** is off (see above)
- Check that `https://stream.home-server.me/identity` responds and that the `newt` container is running
- Have the user restart the Plex app so it re-tests connections

### Local devices treated as remote

- Add the subnet to **LAN Networks**

### Investigating after the fact

Plex rotates its own logs within a day. `plex-log-media-server` keeps 30 days of `Plex Media Server.log`, both in Dozzle and as files on disk (see `README.md` → *Plex Log Archive*). In Dozzle, search the `plex-log-media-server` container. On the server:

```bash
cd ~/docker/plex/log-archive
# Bitrate caps requested by clients, per user
zgrep -h "Request:.*maxVideoBitrate=.*Token (" plex-media-server-*.log* |
  sed -E 's/.*maxVideoBitrate=([0-9]+).*Token \(([^)]*)\).*/\2 \1 kbps/' | sort | uniq -c
# Relay activity

zgrep -h "startRelay\|PlexRelay" plex-media-server-*.log*
```
