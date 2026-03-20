# Plan: Add AdGuard Home Network-Wide Ad Blocker

## TL;DR

Deploy AdGuard Home as a Docker container on the homeserver (192.168.1.166), then configure the UniFi Cloud Gateway Ultra to hand out AdGuard's IP as the DNS server via DHCP. All LAN devices (including iOS) will automatically route DNS through AdGuard, blocking ads network-wide with zero per-device configuration.

**Why AdGuard Home over Pi-hole:** AdGuard Home has a cleaner modern UI, built-in REST API, simpler Docker setup (single container vs Pi-hole's two), native HTTPS admin panel, and better Homepage widget support. Both are excellent; AdGuard is the more streamlined choice for this stack.

---

## Phase 1: Docker Compose Setup

### Step 1: Create `adguard/` directory structure

- [x] Create `adguard/compose.yml` — Docker Compose service definition
- [x] Create `adguard/start.sh` — Start script (executable, same pattern as other stacks)

### Step 2: Write `adguard/compose.yml`

Service definition following existing patterns:
- Image: `adguard/adguardhome:v0.107.55` (pinned for Renovate tracking)
- `env_file: - ../.env` for PUID/PGID/TZ
- Volumes:
  - `${DOCKER_DATA}/adguard/work:/opt/adguardhome/work` (runtime data)
  - `${DOCKER_DATA}/adguard/conf:/opt/adguardhome/conf` (configuration & persistence)
- Ports:
  - `192.168.1.166:53:53/tcp` and `192.168.1.166:53:53/udp` — DNS bound to LAN IP (avoids systemd-resolved conflict)
  - `3001:3000` — Admin web UI (use 3001 to avoid conflict with Homepage on 3000)
- `restart: unless-stopped`
- Join `media-net` network (for Gatus monitoring and Homepage widget access)
- Healthcheck: `wget --spider -q http://localhost:3000` or `nslookup localhost 127.0.0.1`
- DNS: `dns: [1.1.1.1, 1.0.0.1, 8.8.8.8]` — AdGuard itself needs upstream DNS that bypasses itself
- `cap_add: [NET_ADMIN]` — needed for DHCP capabilities (optional but good practice)

### Step 3: Write `adguard/start.sh`

- [x] Following existing start.sh pattern — simple `docker compose pull && docker compose up -d`

---

## Phase 2: Integration with Existing Infrastructure

### Step 4: Add to `scripts/start.sh` STACKS array

- [x] Add `"adguard"` to the STACKS array, positioned **before** `monitoring` (DNS is foundational)

### Step 5: Add Homepage dashboard entry

- [x] In `homepage/services.yaml`, add AdGuard Home under the **Infrastructure** section
- Icon: `adguard-home.png`
- Port: 3001
- Widget type: `adguard` (Homepage has native AdGuard Home widget support)
- Widget fields: queries, blocked, filtered percentage
- The widget needs AdGuard admin credentials — add `ADGUARD_USER` and `ADGUARD_PASS` to `.env` / `.env.example`

### Step 6: Add Gatus health check

- [x] In `monitoring/config.yaml`, add AdGuard Home endpoint under Infrastructure group
- URL: `http://adguard:3000` (internal container port via media-net)
- Conditions: `[STATUS] == 200`, `[RESPONSE_TIME] < 500`
- Discord alert on failure (DNS is critical infrastructure)

### Step 7: Update `.env.example`

- [x] Add placeholder entries for AdGuard Home credentials (used by Homepage widget):
ADGUARD_USER=admin
ADGUARD_PASS=XXXXXXXX


### Step 8: Add GitHub Actions deployment workflow (*parallel with step 4*)

- [x] Create `.github/workflows/deploy-adguard.yml` following existing deploy workflow pattern, using the reusable `deploy-service` action. Triggers on changes to `adguard/**`.

---

## Phase 3: UniFi Network Configuration

### Step 9: Verify homeserver has static DNS (Important — prevents circular dependency)

- [ ] Confirm the homeserver's DNS is set statically to external resolvers (not DHCP-assigned)

Once UniFi DHCP points all clients to AdGuard, the homeserver itself would also receive AdGuard as its DNS via DHCP. This creates a circular dependency on boot: Docker needs DNS to pull images → AdGuard hasn't started yet → pull fails.

**Fix:** Check:
- `/etc/netplan/*.yaml` — look for `nameservers:` section with `1.1.1.1`, `8.8.8.8`
- Or `/etc/systemd/resolved.conf` — check `DNS=` line
- The server likely has a DHCP reservation in UniFi for IP `192.168.1.166` — but DNS assignment comes from DHCP regardless of IP reservation

If the server uses DHCP for DNS, set a static netplan config with explicit nameservers (simplest fix).

### Step 10: Configure UniFi DHCP to use AdGuard as DNS

- [ ] Set DHCP DNS to AdGuard in UniFi UI

In the UniFi Network controller UI (Cloud Gateway Ultra):
1. Go to **Settings → Networks → Default (or your LAN network) → DHCP**
2. Set **DHCP Name Server** to **Manual**
3. Enter `192.168.1.166` as the **only** DNS server (no secondary — see Decisions)
4. Save

After this, all devices that renew their DHCP lease will get AdGuard as their DNS server. Force renewal on iOS: toggle WiFi off/on, or wait for the lease to expire.

### Step 11: (Optional, post-verify) Add DNS interception firewall rule for hardcoded-DNS devices

- [ ] Create DNAT rule in UniFi to intercept rogue DNS traffic

Some IoT devices (Chromecast, Google Home, Fire TV Stick, some smart TVs) ignore DHCP DNS and use hardcoded `8.8.8.8` or `8.8.4.4`. To catch these:

In UniFi UI → **Settings → Firewall & Security → Port Forwarding**:
- Create a DNAT rule that intercepts all outbound UDP/TCP port 53 traffic **not** destined for `192.168.1.166` and redirects it to `192.168.1.166:53`
- This forces all DNS through AdGuard regardless of device configuration
- **Note:** Do this after verifying basic AdGuard setup works (Steps 1–10). This is an enhancement, not a requirement for initial setup.

---

## Phase 4: AdGuard Home Initial Configuration

### Step 12: First-run setup via AdGuard web UI

- [ ] Complete AdGuard Home initial setup wizard

After starting the container, access `http://192.168.1.166:3001`:
1. Set admin username/password (save to `.env` for Homepage widget)
2. Configure upstream DNS servers: `1.1.1.1`, `1.0.0.1`, `8.8.8.8` (same as existing services use)
3. Enable default blocklists (AdGuard Default, OSTS, etc.)
4. Set rate limit to 0 (disable, since this is a trusted LAN)
5. Optionally enable DNSSEC validation

### Step 13: Update README / documentation

- [ ] Add AdGuard Home to the repository README
- Service description and port
- UniFi DHCP configuration steps
- How to access the admin panel
- Troubleshooting (how to verify DNS is routing through AdGuard)

---

## Relevant Files

| File | Action |
|------|--------|
| `adguard/compose.yml` | **Create** — service definition |
| `adguard/start.sh` | **Create** — start script |
| `scripts/start.sh` | **Modify** — add to STACKS array |
| `homepage/services.yaml` | **Modify** — add dashboard card |
| `monitoring/config.yaml` | **Modify** — add health check |
| `.env.example` | **Modify** — add credential placeholders |
| `.github/workflows/deploy-adguard.yml` | **Create** — CI/CD deployment |
| `.github/copilot-instructions.md` | **Modify** — update service stacks table (optional) |

**Reference patterns from:**
- `monitoring/compose.yml` — Simple compose pattern with media-net and Gatus
- `home-assistant/compose.yml` — Simple service with env_file and healthcheck

---

## Verification

1. **Container health:** `docker compose -f adguard/compose.yml ps` — should show healthy
2. **DNS resolution:** `nslookup google.com 192.168.1.166` — should resolve successfully
3. **Ad blocking:** `nslookup ads.google.com 192.168.1.166` — should return `0.0.0.0` or NXDOMAIN
4. **DHCP propagation:** On iOS, go to Settings → Wi-Fi → (i) on your network → check DNS shows `192.168.1.166`
5. **Homepage widget:** Verify AdGuard card appears on dashboard with query stats
6. **Gatus monitoring:** Check `http://192.168.1.166:8082` shows AdGuard Home as healthy
7. **Ad test:** Visit `https://d3ward.github.io/toolz/adblock.html` from iOS to verify ads are blocked
8. **Existing services unaffected:** Verify Sonarr/Radarr/Prowlarr can still reach indexers (they use hardcoded DNS, so should be fine)
9. **DNS interception (if step 11 done):** From a device with hardcoded DNS, `nslookup example.com 8.8.8.8` should still route through AdGuard (visible in AdGuard query log)

---

## Decisions

- **AdGuard Home** over Pi-hole — simpler Docker setup, better REST API, native Homepage widget
- **Plain DNS only (port 53)** — sufficient for LAN ad blocking; DoH/DoT can be added later
- **LAN-only access** — no Cloudflare Tunnel exposure for the admin panel
- **Bind port 53 to LAN IP** (`192.168.1.166:53:53`) — avoids systemd-resolved conflict
- **Manual UniFi DHCP config** — one-time UI setting, not worth automating via fragile undocumented API
- **No secondary DNS fallback** — AdGuard is the sole DNS server for maximum ad blocking. iOS/macOS do parallel DNS queries to all servers, so a secondary like `1.1.1.1` would cause ~50% of traffic to bypass ad blocking. Resilience via: Docker auto-restart, Gatus Discord alerts (60s detection), and manual UniFi app DNS switch as emergency escape hatch.
- **Existing services keep hardcoded DNS** — services like Sonarr/Radarr already have `dns: [1.1.1.1, ...]` which is correct; they should bypass ad blocking to avoid breaking tracker/API connections
- **Homeserver needs static DNS** — to avoid circular dependency on boot (Docker needs DNS before AdGuard starts)

---

## Further Considerations

1. **Existing `dns:` directives on media services** — Currently, services like Sonarr, Plex, etc. have hardcoded `dns: [1.1.1.1, 1.0.0.1, 8.8.8.8]`. These should stay as-is — you don't want ad blocking interfering with tracker connections or API calls.

2. **AdGuard Home backup strategy** — AdGuard's config lives in `${DOCKER_DATA}/adguard/conf/`. Consider whether this should be part of any existing backup routines.

3. **Future: second AdGuard instance** — If you ever add a Raspberry Pi or second device, running a second AdGuard Home there as secondary DNS gives true redundancy with full ad blocking on both.

4. **False positives** — Ad blocking will occasionally break login flows, captchas, payment processors, or streaming services. AdGuard's query log makes it easy to spot and whitelist domains. Expect some day-1 tuning.

5. **DNS-over-HTTPS bypass** — Some browsers (Chrome, Firefox) and apps use built-in DoH that bypasses system DNS entirely. Safari on iOS (the main use case) respects system DNS. If needed later, AdGuard can block DoH endpoints (e.g., `dns.google`) to force fallback.