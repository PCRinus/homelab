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

## Notes

- `configuration.yaml` is mounted **read-only** - edit it in this repo
- `secrets.yaml` is mounted **read-only** - edit it in this repo (gitignored)
- Automations, scripts, and scenes are **read-write** so the Home Assistant UI can modify them
- After editing through the UI, remember to commit changes back to this repo
