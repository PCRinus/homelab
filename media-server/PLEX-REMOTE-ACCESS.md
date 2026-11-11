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

### Devices at home connect directly

Plex runs with `network_mode: host` (`media-server/compose.yml`), so it sees the host's LAN address and advertises `https://192-168-1-166.<hash>.plex.direct:32400` to plex.tv as a **local** connection. Home devices (Apple TV, phones, TVs) use it and stream straight from the server instead of out to the VPS and back. Plex also classifies them as LAN clients, and GDM discovery (32410-32414/udp) works on the LAN.

With the Plex container on a Docker bridge network, Plex advertised only its unreachable container IP (`172.18.0.17`) as local, so every home device went through the VPS. A custom `plex.direct` LAN URL did not fix that: plex.tv lists custom URLs as `remote`, and the Android app went back to `stream.` for playback.

Other containers still reach Plex as `http://plex:32400`: each consumer (newt, cloudflared, Sonarr, Sonarr Anime, Radarr, Bazarr, Gatus, the stream watchdog, Homepage) has `extra_hosts: plex:host-gateway`, which resolves `plex` to the host. Their requests keep arriving from their `media-net` addresses, which Plex treats as a local subnet, so it still honours `X-Forwarded-For` from newt and remote users stay remote.

`192-168-1-166.<hash>.plex.direct` resolves to `192.168.1.166` through public DNS. A DNS server with rebind protection (router or AdGuard) would block it; neither does today. The router should keep `192.168.1.166` reserved for the server.

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
| Custom server access URLs | `https://stream.home-server.me:443` | Plex.tv advertises this URL to clients. The `:443` suffix is required (it fixes iOS downloads and other client quirks). No LAN URL is needed: Plex advertises its LAN address itself (see *Devices at home connect directly*). |
| LAN Networks | `192.168.1.0/24,100.64.0.0/10` | Home LAN and Tailscale/CGNAT addresses count as local (no remote bandwidth rules) |
| Enable Relay | **Off** | Without this, clients that briefly can't reach `stream.` (e.g. during a Plex restart) fall back to Relay and stay capped at 2 Mbps until the app reconnects |
| Secure connections | Preferred | TLS is terminated on the VPS |

**Settings → Remote Access** stays disabled. Port mapping cannot work behind CGNAT, and the custom URL above replaces it.

Saving publishes the new connection list to plex.tv right away; Plex doesn't need a restart. The same change through the API (no restart, safe while people are watching):

```bash
P="$HOME/docker/plex/config/Library/Application Support/Plex Media Server"
T=$(grep -o 'PlexOnlineToken="[^"]*' "$P/Preferences.xml" | cut -d'"' -f2)
curl -s -X PUT -H "X-Plex-Token: $T" --get \
  --data-urlencode "customConnections=https://stream.home-server.me:443" \
  http://localhost:32400/:/prefs
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

Run this on the homeserver. Expected output: a remote `stream.home-server.me` connection, a local `192-168-1-166...plex.direct` connection (plus local entries for the host's Docker bridge addresses, which clients can't reach and skip), and no `RELAY` line once Relay is disabled.

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

### Stream watchdog (stalls, transcoder failures, NIC drops)

Tautulli misses most playback problems. Its buffer notification needs 10 buffer events, sessions shorter than 2 minutes are not recorded at all, and it cannot see transcoder errors. `stream-watchdog` (`monitoring/compose.yml`, script in `monitoring/stream-watchdog/watchdog.py`) follows `Plex Media Server.log` and posts to Discord when:

| Alert | Trigger (defaults, env-tunable) |
|-------|-------------------------------|
| **Plex stall** | A client reports buffering mid-playback for 15 s (`STALL_ALERT_SECONDS`), a start or seek takes 20 s (`STARTUP_ALERT_SECONDS`), 3 rebuffers within 10 min, or the viewer stops while buffering. One alert per client per 5 min; stalls of 60 s or more always get through |
| **Plex transcoder error** | The transcoder logs an error for a session someone is watching, e.g. the Intel VAAPI decoder failing (`Failed to sync surface ... internal decoding error`) |
| **Plex transcoder fell back to software** | A viewer's video transcode runs with a CPU encoder (`libx264`/`libx265`), usually right after a GPU failure. 4K/HDR in software runs at about realtime here, so the picture freezes or the stream buffers |
| **Server NIC link dropped** | `/sys/class/net/enp46s0/carrier_changes` increases. Gatus checks link speed only every 5 min, so it misses drops that last a few seconds |

The webhook is the first of `STREAM_WATCHDOG_DISCORD_WEBHOOK_URL`, `GATUS_DISCORD_WEBHOOK_URL`, `DISCORD_WEBHOOK_URL` that Discord accepts. It is checked at startup, and the log says which one is used (`Discord webhook: using ...`). A deleted webhook returns 404, and alerts would otherwise be lost silently.

Each alert includes NIC throughput, qBittorrent download/upload speed and active torrents, and every Plex session with its decision (direct play / transcode hw or sw, speed, throttled). A home device that reaches Plex through the VPS (client IP = home public IP) is flagged.

It also prints a `metrics` line (NIC, qBittorrent, Plex sessions) every 30 s while something is playing (every 5 min otherwise). Find it in Dozzle under `stream-watchdog`.

Check detection against an archived day, without posting to Discord:

```bash
cd ~/homeserver/monitoring
docker compose run --rm --no-deps stream-watchdog --replay /archive/plex-media-server-2026-11-02.log.gz
```

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

### Home devices still stream through the VPS

Requests through the VPS reach Plex from the `newt` address and carry `X-Real-Ip` set to the home public IP. Check which devices do that:

```bash
cd ~/docker/plex/log-archive
zcat -f plex-media-server-*.log* | grep -o "Request: \[[0-9.]*:" | sort | uniq -c | sort -rn   # 192.168.1.x = direct LAN
```

- Restart the Plex app on the device so it re-tests its connections
- Check that plex.tv lists `192-168-1-166...plex.direct` as `local` (see *Verifying*). If it doesn't, check that the `plex` container still has `network_mode: host`
- Check that the name resolves on the device's network: `dig +short 192-168-1-166.f4edb5ca1ae84f188344f570115415c8.plex.direct` must return `192.168.1.166`. A DNS server with rebind protection (router or AdGuard) would block it; allow `plex.direct` there

### Investigating after the fact

Plex rotates its own logs within a day. `plex-log-media-server` keeps 30 days of `Plex Media Server.log`, both in Dozzle and as files on disk (see `README.md` → *Plex Log Archive*). In Dozzle, search the `plex-log-media-server` container. On the server:

```bash
cd ~/docker/plex/log-archive
# Bitrate caps requested by clients, per user
zgrep -h "Request:.*maxVideoBitrate=.*Token (" plex-media-server-*.log* |
  sed -E 's/.*maxVideoBitrate=([0-9]+).*Token \(([^)]*)\).*/\2 \1 kbps/' | sort | uniq -c
# Relay activity

zgrep -h "startRelay\|PlexRelay" plex-media-server-*.log*
# What a client reported, per playback: state, position, stall seconds
zgrep -h "GET /:/timeline" plex-media-server-2026-11-02.log.gz | grep "Token (Daniel Homan)" |
  grep -oE "^.{24}|state=[a-z]+|[?&]time=[0-9]+|timeStalled=[0-9]+" | paste -sd' ' | sed 's/ Nov/\nNov/g'
# GPU decode failures, and software (libx264) video transcodes
zgrep -h "Failed to sync surface" plex-media-server-*.log* | cut -c1-24
zgrep -h "Job running" plex-media-server-*.log* | grep -- "-codec:0 libx264" | cut -c1-24
```

Plex writes its log timestamps in the container's local time (`TZ`, Europe/Bucharest), while the archive files are split by UTC day.
