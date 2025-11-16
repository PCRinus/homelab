# GitHub Actions Setup Guide

This repository uses GitHub Actions with Tailscale to automatically deploy Docker Compose services when their configuration files change.

## Prerequisites

1. **Tailscale Account** with admin access
2. **SSH Access** to your homelab server
3. **GitHub Repository** with admin access

## Setup Steps

### 1. Create Tailscale OAuth Client

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth)
2. Click **Generate OAuth Client**
3. Add a tag for CI/CD access (e.g., `tag:ci`)
4. Select the scope: **auth_keys** (or all read scopes)
5. Save your **Client ID** and **Client Secret**

### 2. Configure Tailscale ACLs

Go to [Tailscale Admin Console → Access Controls](https://login.tailscale.com/admin/acls)

Add the following to your Tailscale policy file to allow the CI tag to access your homelab server:

**Option 1: Allow access to all devices (simpler for testing)**
```json
{
  "tagOwners": {
    "tag:ci": []
  },
  "grants": [
    {
      "src": ["tag:ci"],
      "dst": ["*"],
      "ip": ["*:*"]
    }
  ]
}
```

**Option 2: Restrict to SSH only (more secure)**

```json
{
  "tagOwners": {
    "tag:ci": []
  },
  "grants": [
    {
      "src": ["tag:ci"],
      "dst": ["*"],
      "app": {
        "tailscale.com/cap/ssh": [{
          "users": ["autogroup:members"]
        }]
      }
    }
  ]
}
```

**What this does:**
- Creates a `tag:ci` that admins can use
- Option 1: Allows devices with `tag:ci` to access all ports/protocols
- Option 2: Uses Tailscale SSH capabilities for more control
- `"dst": ["*"]` means all devices in your tailnet

### 3. Generate SSH Key for GitHub Actions

On your local machine, generate a new SSH key:

```bash
ssh-keygen -t ed25519 -C "github-actions@homelab" -f ~/.ssh/github_actions_key -N ""
```

Then, add the public key to your server's `~/.ssh/authorized_keys`:

```bash
# Copy the public key to your server
cat ~/.ssh/github_actions_key.pub | ssh your-user@homelab 'cat >> ~/.ssh/authorized_keys'

# Or use ssh-copy-id
ssh-copy-id -i ~/.ssh/github_actions_key.pub your-user@homelab
```

### 4. Add GitHub Secrets

Go to your GitHub repository settings: **Settings → Secrets and variables → Actions → New repository secret**

Add the following secrets:

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `TS_OAUTH_CLIENT_ID` | `[Your OAuth Client ID]` | Tailscale OAuth client ID |
| `TS_OAUTH_SECRET` | `[Your OAuth Client Secret]` | Tailscale OAuth client secret |
| `SSH_PRIVATE_KEY` | `[Content of github_actions_key]` | Private SSH key (entire file content including `-----BEGIN` and `-----END` lines) |
| `SSH_USER` | `[Your SSH username]` | Username on the homelab server (e.g., `mircea`) |

To get the private key content:
```bash
cat ~/.ssh/github_actions_key
```

## How It Works

1. **Trigger**: When you push changes to any `compose.yml` file (or specific paths for some services)
2. **Connect**: GitHub runner connects to your Tailscale network using the OAuth credentials
3. **SSH**: Uses `appleboy/ssh-action` to connect to your homelab server via MagicDNS (`homelab`)
4. **Deploy**: Runs `docker compose pull && docker compose up -d` in the appropriate directory
5. **Cleanup**: Tailscale ephemeral node is automatically removed after workflow completes

## Workflows Created

- `deploy-portainer.yml` - Triggered by changes to `portainer/compose.yml`
- `deploy-dozzle.yml` - Triggered by changes to `dozzle/compose.yml`
- `deploy-home-assistant.yml` - Triggered by changes to `home-assistant/compose.yml`
- `deploy-homepage.yml` - Triggered by changes to `homepage/**`
- `deploy-media-server.yml` - Triggered by changes to `media-server/compose.yml`
- `deploy-minecraft-servers.yml` - Triggered by changes to `minecraft-servers/**`
- `deploy-uptime-kuma.yml` - Triggered by changes to `uptime-kuma/compose.yml`
- `deploy-cloudflare-tunnel.yml` - Triggered by changes to `cloudflare-tunnel/compose.yml` or `config.yml`

## Testing

After setup, test by making a small change to any compose file and pushing:

```bash
# Example: add a comment to portainer compose file
echo "# Updated $(date)" >> portainer/compose.yml
git add portainer/compose.yml
git commit -m "test: trigger portainer deployment"
git push
```

Then check the **Actions** tab in your GitHub repository to see the workflow run.

## Troubleshooting

### Workflow fails with "Connection refused"
- Verify your Tailscale ACLs allow `tag:ci` to access `homelab:22`
- Check that MagicDNS is enabled in your tailnet
- Ensure your homelab server's hostname in Tailscale is `homelab`

### SSH authentication fails
- Verify the SSH_PRIVATE_KEY secret contains the complete private key (including `-----BEGIN` and `-----END` lines)
- Ensure the public key is in your server's `~/.ssh/authorized_keys`
- Check SSH_USER matches your actual username on the server
- Verify SSH service is running on your server: `sudo systemctl status ssh`

### Docker commands fail
- Ensure your SSH user has permission to run docker commands (member of `docker` group):
  ```bash
  sudo usermod -aG docker $USER
  ```
- Verify the paths in workflows match your actual directory structure
- Check that Docker Compose is installed on your server

## Security Notes

- OAuth credentials create ephemeral nodes that are automatically cleaned up
- SSH keys are stored as GitHub encrypted secrets
- No ports need to be exposed on your home network
- All communication happens through Tailscale's encrypted WireGuard tunnels
