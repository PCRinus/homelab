# Buildarr Configuration

This directory contains the Buildarr configuration for managing the *arr stack (Sonarr, Prowlarr) as code.

## Setup

1. **Create the secrets file** from the example:
   ```bash
   cd /home/mircea/homeserver/media-server/buildarr
   cp buildarr-secrets.yml.example buildarr-secrets.yml
   ```

2. **Add your API keys** to `buildarr-secrets.yml` (already configured)

3. **Test the configuration** before starting in daemon mode:
   ```bash
   cd /home/mircea/homeserver/media-server
   docker compose run --rm buildarr test-config
   ```

4. **Start Buildarr** with the rest of the stack:
   ```bash
   docker compose up -d buildarr
   ```

5. **Check logs** to verify it connected to all services:
   ```bash
   docker compose logs -f buildarr
   ```

## Files

- `buildarr.yml` - Main configuration (version controlled)
- `buildarr-secrets.yml` - API keys and secrets (NOT version controlled, gitignored)
- `buildarr-secrets.yml.example` - Template for secrets file

## Current Configuration

### Managed Services

✅ **Prowlarr** - Fully configured and managed
- 5 indexers: 1337x, BitSearch, FileList.io, Isohunt2, kickasstorrents.to
- FlareSolverr proxy for cloudflare-protected sites
- App connections to Sonarr and Radarr with full-sync
- Tags for proxy routing

✅ **Sonarr** - Connection configured (minimal settings)
- No settings managed yet

❌ **Radarr** - Temporarily disabled due to compatibility issue with v6.0.4

### What's Managed in Prowlarr

**Indexers:**
- All 5 indexers with their configurations
- FlareSolverr proxy setup
- Indexer-specific settings (priorities, tags, download links)

**App Connections:**
- Sonarr sync with full-sync mode and category mappings
- Radarr sync with full-sync mode and category mappings
- API keys for both connections

**Sync Profiles:**
- Standard profile with RSS, interactive, and automatic search enabled

**Tags:**
- `flaresolverr` tag for proxy routing

### What's NOT Managed (Intentionally)

These settings are commented out because they're typically set once and rarely changed:

- **General Settings**: Host config, port, bind address (managed via Docker)
- **Security**: Authentication, username/password (better managed via UI)
- **Logging**: Log levels
- **Backup**: Backup intervals and retention
- **UI**: Theme, date formats, language preferences

## Schedule

Buildarr runs daily at **3:00 AM** to ensure configuration stays in sync.

## Making Changes

1. Edit `buildarr.yml` for non-secret configuration
2. Edit `buildarr-secrets.yml` for API keys (gitignored)
3. Changes are automatically detected and applied (watch mode enabled)
4. Or restart manually: `docker compose restart buildarr`

## Dumping Current Config

To see what your instances currently have configured:

```bash
docker compose run --rm buildarr sonarr dump-config http://sonarr:8989 > sonarr-dump.yml
docker compose run --rm buildarr prowlarr dump-config http://prowlarr:9696 > prowlarr-dump.yml
``` 

For example, to manage Sonarr's media management settings:

```yaml
sonarr:
  instances:
    sonarr:
      host: "sonarr"
      port: 8989
      protocol: "http"
      api_key: !env "${SONARR_API_KEY}"
      settings:
        media_management:
          rename_episodes: true
          replace_illegal_characters: true
```

See the [Buildarr documentation](https://buildarr.github.io/) for all available settings.

## How It Works

- Buildarr reads the `buildarr.yml` configuration
- It connects to each *arr instance via API
- On the schedule (or when config changes), it ensures the actual configuration matches what's defined
- This prevents configuration drift and enables infrastructure-as-code for your media stack
