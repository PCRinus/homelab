# Plex Remote Access via Cloudflare Tunnel

This guide explains how to configure Plex for direct remote connections through Cloudflare Tunnel, avoiding the low-quality Plex Relay.

## Why This Matters

| Connection Type | Quality | Speed |
|-----------------|---------|-------|
| **Plex Relay** | 1 Mbps (free) / 2 Mbps (paid) | Slow, often transcodes |
| **Direct (Cloudflare Tunnel)** | Original quality | Fast, direct play |

Without proper configuration, mobile clients (Android/iOS) default to Plex Relay because they can't discover your server's custom URL.

## Prerequisites

- Cloudflare Tunnel already configured with Plex ingress (e.g., `plex.home-server.me`)
- Plex accessible via the tunnel URL in a browser

## Configuration Steps

### 1. Access Plex Network Settings

Go to your Plex server:
- Local: `http://localhost:32400/web`
- Or via tunnel: `https://plex.home-server.me`

Navigate to: **Settings → Network → Show Advanced**

### 2. Set Custom Server Access URLs

In the **"Custom server access URLs"** field, enter:

```
https://plex.home-server.me:443
```

⚠️ **Important:** The `:443` port suffix is **required** - it fixes iOS download issues and other client quirks.

This tells Plex's cloud service to direct clients to your Cloudflare tunnel URL instead of using Relay.

### 3. Configure LAN Networks

In the **"LAN Networks"** field, add your local network:

```
192.168.1.0/24
```

Or if you also use Tailscale/CGNAT VPN:

```
192.168.1.0/24,100.64.0.0/10
```

This ensures devices on your home network are recognized as "local" and get unrestricted bandwidth.

### 4. Remote Access Settings

- **Enable Relay:** Leave **enabled** (acts as fallback if tunnel fails)
- **Remote Access:** Can be left **disabled** (not needed with Cloudflare tunnel)

### 5. Secure Connections

Set **"Secure connections"** to **"Preferred"** (not required, since Cloudflare handles TLS).

### 6. Save and Restart

1. Click **Save Changes**
2. Restart Plex:
   ```bash
   cd /home/mircea/homeserver/media-server && docker restart plex
   ```

### 7. Refresh Mobile Clients

On Android/iOS Plex apps:
1. **Sign out** completely
2. **Sign back in**

This forces the app to fetch the updated server connection info.

## Cloudflare Configuration (Optional but Recommended)

To prevent caching issues (especially iOS Direct Play seeking):

### Disable Caching for Your Domain

1. Go to **Cloudflare Dashboard → Websites → your domain → Caching**
2. Set **"Caching Level"** to **"No query string"**
3. Create a **Cache Rule**:
   - Rule name: `Disable caching`
   - When: Hostname **ends with** `home-server.me`
   - Cache eligibility: **Bypass cache**

## Verifying It Works

### Check Connection Type

1. Play media on a remote client
2. On your Plex server, go to **Settings → Dashboard**
3. Look at "Now Playing" - connection should show **"secure"** or **"direct"**, NOT **"relay"**

### Browser DevTools

1. Open `https://app.plex.tv` in browser
2. Press F12 → Network tab
3. Play media
4. Requests should go to `plex.home-server.me`, NOT `*.plex.services.conductor.plex.tv`

### Test from Mobile Data

1. Turn off WiFi on your phone
2. Open Plex app and play something
3. Check Dashboard for connection type

## Troubleshooting

### Clients still using Relay

- Ensure you included `:443` in the custom URL
- Sign out and back in on the client
- Wait a few minutes for Plex cloud to propagate the change

### iOS downloads stuck on "Queued"

- Verify `:443` is in the custom URL
- Check Cloudflare caching is set to "No query string"

### Local devices treated as remote

- Add your subnet to "LAN Networks" (e.g., `192.168.1.0/24`)

## Source

This guide is based on: [How to set up free, secure, high-quality remote access for Plex](https://mythofechelon.co.uk/blog/2024/1/7/how-to-set-up-free-secure-high-quality-remote-access-for-plex) by Ben Hooper (mythofechelon).
