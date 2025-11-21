# Cloudflare Tunnel & Terraform Configuration

This directory contains the infrastructure-as-code setup for managing Cloudflare resources including DNS records, Zero Trust Tunnels, and zone settings.

## 📁 Directory Structure

```
cloudflare-tunnel/
├── compose.yml              # Docker Compose for running cloudflared
├── tunnel-token            # Tunnel authentication token (gitignored)
├── main.tf                 # Main Terraform configuration (provider, variables, zone settings)
├── generated_dns_records.tf # Imported DNS records
├── generated_tunnels.tf    # Imported tunnel resources
├── terraform.tfvars        # Variable values (gitignored - contains sensitive data)
└── README.md              # This file
```

## 🔐 Prerequisites

### Required Tools
- **Terraform** (`~> 1.5+`)
- **Docker & Docker Compose** (for running the tunnel)
- **cf-terraforming** (installed at `/usr/local/bin/cf-terraforming`)

### Environment Variables
Set these before running Terraform commands:

```bash
export CLOUDFLARE_API_TOKEN="your-api-token-here"
```

### API Token Permissions
Your Cloudflare API token needs:
- **Zone:Read** - View zone information
- **DNS:Edit** - Manage DNS records  
- **Account:Read** - View account information
- **Cloudflare Tunnel:Edit** - Manage tunnels
- **Zone Settings:Edit** - Modify zone settings (TLS, SSL, etc.)

## 🚀 Terraform Usage

### Initialize Terraform
```bash
terraform init
```

### View Changes
```bash
terraform plan
```

### Apply Changes
```bash
terraform apply
```

### Import Existing Resources
If you need to import additional resources:

```bash
# Generate Terraform config from Cloudflare
cf-terraforming generate \
  --token $CLOUDFLARE_API_TOKEN \
  -z <zone-id> \
  --resource-type "cloudflare_dns_record" > new_resources.tf

# Generate import commands
cf-terraforming import \
  --token $CLOUDFLARE_API_TOKEN \
  -z <zone-id> \
  --resource-type "cloudflare_dns_record" > import.sh

# Execute imports
bash import.sh
```

## 🔒 Cloudflare Tunnel Setup

### How It Works

1. **Tunnel Definition** (Terraform) - Creates the tunnel in Cloudflare
2. **Tunnel Configuration** (Terraform or Local) - Defines ingress rules
3. **Tunnel Daemon** (Docker) - Runs cloudflared to establish the connection

### Active Tunnel

- **Tunnel ID**: `0ba69785-f553-4e75-ae68-1f3f990e573d`
- **Name**: `homeserver`
- **Config Source**: `cloudflare` (managed via Terraform)

### Ingress Rules

Current services exposed through the tunnel:

| Hostname | Service | Port |
|----------|---------|------|
| `plex.home-server.me` | Plex Media Server | 32400 |
| `ha.home-server.me` | Home Assistant | 8123 |

### Managing the Tunnel

**Start/Restart the tunnel:**
```bash
sudo docker compose up -d
sudo docker compose restart
```

**View tunnel logs:**
```bash
sudo docker compose logs -f cloudflared
```

**Stop the tunnel:**
```bash
sudo docker compose down
```

### Adding New Services

1. **Add to `config.yml`:**
```yaml
ingress:
  - hostname: new-service.home-server.me
    service: http://localhost:PORT
  - hostname: plex.home-server.me
    service: http://localhost:32400
  - hostname: ha.home-server.me
    service: http://localhost:8123
  - service: http_status:404
```

2. **Create DNS record in Terraform:**
```hcl
resource "cloudflare_dns_record" "new_service" {
  zone_id = var.zone_id
  name    = "new-service"
  content = "0ba69785-f553-4e75-ae68-1f3f990e573d.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}
```

3. **Apply changes:**
```bash
terraform apply
sudo docker compose restart
```

## 🔧 Configuration Files

### terraform.tfvars
```hcl
zone_id    = "your-zone-id"
account_id = "your-account-id"
domain     = "home-server.me"
```

### config.yml
- Used by cloudflared Docker container
- Defines tunnel ingress rules locally
- Must match tunnel config in Terraform for consistency

## 📊 Managed Resources

### DNS Records (4)
- `www.home-server.me` - A record pointing to `203.0.113.10`
- `home-server.me` - CNAME to tunnel
- `plex.home-server.me` - CNAME to tunnel
- `ha.home-server.me` - CNAME to tunnel

### Cloudflare Tunnel (1)
- Tunnel: `homeserver` (`0ba69785-f553-4e75-ae68-1f3f990e573d`)
- Tunnel Config: Remotely managed via Terraform (10 services)

### Zone Settings (3)
- TLS 1.3: Enabled
- Automatic HTTPS Rewrites: Enabled
- SSL Mode: Strict

## ⚠️ Important Notes

### Sensitive Files (Do NOT commit)
- `terraform.tfstate*` - Contains resource IDs and metadata
- `terraform.tfvars` - Contains zone/account IDs
- `tunnel-token` - Tunnel authentication token
- `.terraform/` - Provider binaries

### GitHub Secrets Required
For CI/CD deployment via GitHub Actions:
- `CLOUDFLARE_API_TOKEN` - Terraform API token
- `CLOUDFLARE_TUNNEL_TOKEN` - Base64 encoded tunnel token (contents of `tunnel-token` file)
- `TS_AUTHKEY` - Tailscale auth key
- `SSH_PRIVATE_KEY` - SSH key for deployment
- `SSH_USER` - SSH username for deployment

### Zone Settings Warning
Zone settings (TLS 1.3, SSL, HTTPS rewrites) cannot be destroyed via Terraform. They must be manually disabled in the Cloudflare dashboard if needed.

### State Management
- State is stored locally in `terraform.tfstate`
- Consider using remote state (S3, Terraform Cloud) for team collaboration
- Always backup state files before major changes

## 🐛 Troubleshooting

### Tunnel Not Working
1. Check if container is running: `sudo docker ps | grep cloudflared`
2. Check logs: `sudo docker compose logs cloudflared`
3. Verify tunnel status in Cloudflare dashboard
4. Ensure credentials file exists: `ls -la *.json`

### Terraform Permission Errors
- Verify API token has all required permissions
- Update token in environment: `export CLOUDFLARE_API_TOKEN="new-token"`

### DNS Not Resolving
- Verify DNS records in Cloudflare dashboard
- Check if zone is active
- Ensure nameservers are correctly configured

## 📚 Additional Resources

- [Cloudflare Terraform Provider Docs](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [cf-terraforming GitHub](https://github.com/cloudflare/cf-terraforming)
- [Terraform Best Practices](https://developers.cloudflare.com/terraform/advanced-topics/best-practices/)
