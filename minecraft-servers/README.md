# Minecraft Servers

This directory contains Docker Compose configurations for multiple Minecraft servers using a shared common configuration.

## Structure

```
minecraft-servers/
├── common.compose.yml           # Shared configuration (base image, mods, settings)
├── servers/
│   ├── world-gen-server.compose.yml
│   └── survival-island.compose.yml
├── mods/
│   ├── performance.txt          # Shared performance mods
│   ├── content.txt              # Shared content/gameplay mods
│   └── world-generation-extra.txt # World-gen-only extra mods
├── resolve-modrinth-mods.sh     # Validates and resolves compatible mod versions
├── .env                         # Environment variables (CF_API_KEY, TZ)
└── README.md                    # This file
```

## Common Configuration

`common.compose.yml` provides reusable configuration through YAML anchors:

- **`x-minecraft-base`**: Base service config (image, EULA, ops, timezone, etc.)

Shared mods are now managed from files in `mods/` and resolved automatically before startup.

## Environment Variables

The `.env` file in this directory is automatically loaded by Docker Compose and contains:

- `CF_API_KEY`: CurseForge API key for mod downloads
- `TZ`: Timezone (Europe/Bucharest)

These variables are available to all compose files in this directory.

## Starting a Server

From this directory, run:

```bash
# Start world generation server
docker compose -f common.compose.yml -f servers/world-gen-server.compose.yml up -d

# Start survival island server
docker compose -f common.compose.yml -f servers/survival-island.compose.yml up -d

# View logs
docker compose -f common.compose.yml -f servers/world-gen-server.compose.yml logs -f

# Stop a server
docker compose -f common.compose.yml -f servers/world-gen-server.compose.yml down
```

Or start all Minecraft servers with compatibility validation:

```bash
./start.sh
```

Start only one specific server:

```bash
./start.sh survival-island
```

Start a subset of servers:

```bash
./start.sh world-gen-server survival-island
```

To set a specific Minecraft version for startup and mod resolution:

```bash
MC_VERSION=1.21.11 ./start.sh
```

`start.sh` runs `resolve-modrinth-mods.sh` first, which:
- reads mod slugs from `mods/*.txt`
- checks compatibility against the selected Minecraft version and Fabric loader
- writes resolved mod references to `.generated-modrinth.env`
- exports those values to Docker Compose (`MODRINTH_PROJECTS_*`)

If `.generated-modrinth.env` already matches the target `MC_VERSION`, `start.sh` reuses it and skips re-resolving mods.

## Creating a New Server

1. **Copy an existing server file:**
   ```bash
  cp servers/world-gen-server.compose.yml servers/my-new-server.compose.yml
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
  ./start.sh my-new-server
   ```

## Example Server Configuration

```yaml
services:
  mc:
    container_name: minecraft-server-my-server
    ports:
      - "25567:25565"
    environment:
      MEMORY: "4096M"
      MAX_PLAYERS: "8"
      SEED: "123456789"
      MODRINTH_PROJECTS: "${MODRINTH_PROJECTS_SURVIVAL_ISLAND}"
    volumes:
      - /home/mircea/docker/minecraft-server-my-server:/data
```

Place this file under `servers/` so `start.sh` and `stop.sh` will manage it.

## Modifying Common Configuration

To add mods or change settings for **all servers**:

1. Edit `mods/performance.txt` and/or `mods/content.txt`
2. Restart affected servers:
   ```bash
  ./start.sh
   ```

## Server-Specific Mods

World-generation-only mods are in `mods/world-generation-extra.txt`.

To target a specific Minecraft version explicitly, set `MC_VERSION` when running:

```bash
MC_VERSION=1.21.11 ./start.sh
```

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

## Stop All Servers

To stop all Minecraft servers in this directory:

```bash
./stop.sh
```

Stop only one server:

```bash
./stop.sh survival-island
```

Stop a subset of servers:

```bash
./stop.sh world-gen-server survival-island
```
