# Minecraft Servers

This directory contains Docker Compose configurations for multiple Minecraft servers using a shared common configuration.

## Structure

```
minecraft-servers/
├── common.compose.yml           # Shared configuration (base image, mods, settings)
├── .env                         # Environment variables (CF_API_KEY, TZ)
├── world-gen-server.compose.yml # World generation server
├── survival-island.compose.yml  # Survival island server
└── README.md                    # This file
```

## Common Configuration

`common.compose.yml` provides reusable configuration through YAML anchors:

- **`x-minecraft-base`**: Base service config (image, EULA, ops, timezone, etc.)
- **`x-minecraft-common-mods`**: Shared mod list (performance, quality of life, building mods)

## Environment Variables

The `.env` file in this directory is automatically loaded by Docker Compose and contains:

- `CF_API_KEY`: CurseForge API key for mod downloads
- `TZ`: Timezone (Europe/Bucharest)

These variables are available to all compose files in this directory.

## Starting a Server

From this directory, run:

```bash
# Start world generation server
docker compose -f world-gen-server.compose.yml up -d

# Start survival island server
docker compose -f survival-island.compose.yml up -d

# View logs
docker compose -f world-gen-server.compose.yml logs -f

# Stop a server
docker compose -f world-gen-server.compose.yml down
```

## Creating a New Server

1. **Copy an existing server file:**
   ```bash
   cp world-gen-server.compose.yml my-new-server.compose.yml
   ```

2. **Edit the new file** to customize:
   - `container_name`: Unique name for the container
   - `ports`: Change host port (e.g., `25567:25565`)
   - `environment`:
     - `MEMORY`: RAM allocation (e.g., `4096M`)
     - `MAX_PLAYERS`: Player limit
     - `SEED`: World seed (optional)
     - `VIEW_DISTANCE`, `SIMULATION_DISTANCE`: Render settings
     - `MODRINTH_PROJECTS`: Add/remove mods (use `*common-mods` to include shared mods)
   - `volumes`: Update bind mount path to a unique directory

3. **Create the data directory:**
   ```bash
   mkdir -p /home/mircea/docker/minecraft-server-my-new-server
   ```

4. **Start the server:**
   ```bash
   docker compose -f my-new-server.compose.yml up -d
   ```

## Example Server Configuration

```yaml
include:
  - ./common.compose.yml

services:
  minecraft:
    <<: *minecraft-base
    container_name: minecraft-server-my-server
    ports:
      - "25567:25565"
    environment:
      MEMORY: "4096M"
      MAX_PLAYERS: "8"
      SEED: "123456789"
      MODRINTH_PROJECTS: |-
        *common-mods
        create
        ad-astra
    volumes:
      - /home/mircea/docker/minecraft-server-my-server:/data
```

## Modifying Common Configuration

To add mods or change settings for **all servers**:

1. Edit `common.compose.yml`
2. Restart affected servers:
   ```bash
   docker compose -f world-gen-server.compose.yml restart
   docker compose -f survival-island.compose.yml restart
   ```

## Server-Specific Mods

To add mods to **only one server**, list them under `MODRINTH_PROJECTS` after the `*common-mods` line.

## Port Mapping

Each server needs a unique host port. Current allocations:

- `25565` - world-gen-server
- `25566` - survival-island

## Data Persistence

Server data is stored in `/home/mircea/docker/minecraft-server-<name>/` including:
- World files
- Server properties
- Player data
- Logs

## Resources

- [itzg/minecraft-server Documentation](https://docker-minecraft-server.readthedocs.io/)
- [Modrinth](https://modrinth.com/) - Mod downloads
