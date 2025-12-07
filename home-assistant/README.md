# Home Assistant Configuration

This directory contains version-controlled Home Assistant configuration files.

## Structure

- **`configuration.yaml`** - Main configuration file (read-only in container)
- **`automations.yaml`** - Automations (read-write for UI editing)
- **`scripts.yaml`** - Scripts (read-write for UI editing)
- **`scenes.yaml`** - Scenes (read-write for UI editing)
- **`secrets.yaml.example`** - Template for secrets file

## Setup

### Initial Setup

1. Copy the secrets template:
   ```bash
   cp secrets.yaml.example secrets.yaml
   ```

2. Edit `secrets.yaml` with your actual secret values (file is gitignored)

### Running

```bash
docker compose up -d
```

## Volume Strategy

This setup uses a **hybrid approach**:

- **Configuration files** (this repo):
  - All configs mounted from this repo
  - `secrets.yaml` is gitignored but stored here as source of truth
  - Version controlled (except secrets)
  - Easy to track changes
  
- **Persistent data** (`~/docker/home-assistant`):
  - Database (`home-assistant_v2.db`)
  - Cache and storage (`.storage/`, `.cache/`)
  - Runtime files

## Installing HACS (Home Assistant Community Store)

HACS enables installing custom integrations, themes, and frontend cards (like Mushroom Cards).

### Installation

1. Run the HACS installer inside the container:
   ```bash
   docker exec -it homeassistant bash -c "wget -O - https://get.hacs.xyz | bash -"
   ```

2. Restart Home Assistant:
   ```bash
   docker compose restart
   ```

3. In Home Assistant UI:
   - Go to **Settings** → **Devices & Services** → **Add Integration**
   - Search for **HACS**
   - Follow the GitHub authorization flow

### Recommended HACS Add-ons

After HACS is configured, install these from **HACS** → **Frontend**:

| Add-on | Purpose |
|--------|---------|
| **Mushroom Cards** | Modern, clean card designs |
| **Button Card** | Highly customizable buttons |
| **card-mod** | CSS styling for any card |
| **layout-card** | Better control over card placement |

### Notes

- HACS installs to `/config/custom_components/hacs/` which persists in `~/docker/home-assistant`
- HACS Supervisor add-ons won't work (requires Home Assistant OS), but frontend cards and integrations work fine
- The container needs DNS access to download from GitHub (already configured in `compose.yml`)

## Notes

- `configuration.yaml` is mounted **read-only** - edit it in this repo
- `secrets.yaml` is mounted **read-only** - edit it in this repo (gitignored)
- Automations, scripts, and scenes are **read-write** so the Home Assistant UI can modify them
- After editing through the UI, remember to commit changes back to this repo
