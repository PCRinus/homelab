# Cloudflare Tunnel & Terraform Configuration

This directory contains the infrastructure-as-code setup for managing Cloudflare resources including DNS records, Zero Trust Tunnels, Zero Trust Access (SSO authentication), and zone settings.

## 📁 Directory Structure

```
cloudflare-tunnel/
├── compose.yml              # Docker Compose for running cloudflared
├── tunnel-token            # Tunnel authentication token (gitignored)
├── main.tf                 # Main Terraform configuration (provider, variables, zone settings)
├── dns.tf                  # DNS records
├── tunnel.tf               # Zero Trust tunnel configuration
├── access.tf               # Zero Trust Access configuration (SSO/authentication)
├── r2.tf                   # R2 bucket for Terraform state
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

# Required for R2 state backend
export AWS_ACCESS_KEY_ID="your-r2-access-key"
export AWS_SECRET_ACCESS_KEY="your-r2-secret-key"
```

### API Token Permissions
Your Cloudflare API token needs:
- **Zone:Read** - View zone information
- **DNS:Edit** - Manage DNS records  
- **Account:Read** - View account information
- **Cloudflare Tunnel:Edit** - Manage tunnels
- **Zone Settings:Edit** - Modify zone settings (TLS, SSL, etc.)
- **Access: Organizations, Identity Providers, and Groups:Edit** - Manage Zero Trust identity providers and groups
- **Access: Apps and Policies:Edit** - Manage Zero Trust access applications and policies

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

### Zero Trust Access
- **Identity Provider**: Google OAuth
- **Access Group**: Homelab Authorized Users
- **Protected Services**: `*.home-server.me` (wildcard)
- **Bypassed Services**: Plex, Homepage, Home Assistant

## 🛡️ Zero Trust Access (SSO Authentication)

Zero Trust Access provides Single Sign-On (SSO) authentication for all homelab services using Google as the identity provider.

### How It Works

```
User → Cloudflare Edge → Access Check → Tunnel → Service
                              ↓
                    Google OAuth Login
                    (if not authenticated)
```

1. User visits a protected service (e.g., `sonarr.home-server.me`)
2. Cloudflare Access checks for valid session cookie
3. If no valid session → redirect to Google login
4. After authentication → session cookie set for `*.home-server.me`
5. User can access all protected services without re-authenticating (SSO)

### Access Policies

| Domain | Policy | Description |
|--------|--------|-------------|
| `*.home-server.me` | **Protected** | Requires Google login (7-day session) |
| `plex.home-server.me` | **Bypass** | Uses Plex's own authentication |
| `home-server.me` | **Bypass** | Homepage dashboard (public) |
| `ha.home-server.me` | **Bypass** | Home Assistant (uses own auth + mobile app) |

### Authorized Users

Authorized users are defined in `access.tf` in the `cloudflare_zero_trust_access_group.authorized_users` resource:

```hcl
resource "cloudflare_zero_trust_access_group" "authorized_users" {
  account_id = var.account_id
  name       = "Homelab Authorized Users"

  include = [{
    email = {
      email = "mircea.casapu@gmail.com"
    }
  }]
}
```

To add more users, add additional email blocks:

```hcl
include = [
  { email = { email = "mircea.casapu@gmail.com" } },
  { email = { email = "family.member@gmail.com" } },
]
```

### Adding a New User

New users must be added in **two places** for authentication to work:

#### Step 1: Add to Google Cloud Console (Authentication)

This allows the user to authenticate via Google OAuth:

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Navigate to **APIs & Services** → **OAuth consent screen**
3. Scroll down to **Test users** section
4. Click **+ Add Users**
5. Enter the user's Gmail address (e.g., `newuser@gmail.com`)
6. Click **Save**

> **Note**: The OAuth app is in "Testing" mode, which limits access to explicitly added test users. This is intentional for security — only approved users can authenticate.

#### Step 2: Add to Cloudflare Access Group (Authorization)

This authorizes the user to access your services:

1. Edit `access.tf`
2. Add the new email to the `authorized_users` group:

```hcl
resource "cloudflare_zero_trust_access_group" "authorized_users" {
  account_id = var.account_id
  name       = "Homelab Authorized Users"

  include = [
    { email = { email = "mircea.casapu@gmail.com" } },
    { email = { email = "newuser@gmail.com" } },  # New user
  ]
}
```

3. Commit and push to trigger the deployment pipeline, or run:

```bash
cd cloudflare-tunnel
terraform apply
```

#### Why Both Steps?

| Layer | Purpose | Error if user is missing |
|-------|---------|--------------------------|
| **Google Test Users** | Can they authenticate with Google? | "You don't have access to this app" |
| **Cloudflare Access Group** | Are they authorized to access services? | "Access Denied" after Google login |

### Session Duration

- **Protected services**: 7 days (`168h`)
- **Bypass services**: N/A (no Access session needed)

After 7 days, users will need to re-authenticate via Google.

### Google OAuth Configuration

The Google Identity Provider is configured in `access.tf`. OAuth credentials are stored as:
- `google_oauth_client_id` - Variable in `terraform.tfvars`
- `google_oauth_client_secret` - Variable in `terraform.tfvars`

**Google Cloud Console Setup:**

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project (or use existing)
3. Navigate to **APIs & Services** → **OAuth consent screen**
   - Select **External** user type
   - Fill in app name, support email, and developer email
   - **Scopes**: Leave as default (no additional scopes needed)
     - Cloudflare Access only needs: `openid`, `email`, `profile` (included by default)
   - Add yourself as a **Test user**
   - Leave publishing status as **Testing** (limits to approved test users only)
4. Navigate to **APIs & Services** → **Credentials**
   - Click **+ Create Credentials** → **OAuth client ID**
   - Application type: **Web application**
   - Name: `Cloudflare Access`
   - Authorized redirect URI: `https://pcrinus.cloudflareaccess.com/cdn-cgi/access/callback`
5. Copy **Client ID** and **Client Secret** to `terraform.tfvars`

> **Note on Scopes**: Cloudflare Access only requires basic OpenID Connect scopes (`openid`, `email`, `profile`) which are included by default. You don't need to add any additional scopes in the OAuth consent screen.

> **Note on Publishing Status**: Keep the app in "Testing" mode. This means only explicitly added test users can authenticate — acting as an additional security layer. Users will see a "Google hasn't verified this app" warning on first login, which they can click through.

### Adding a New Protected Service

New services under `*.home-server.me` are automatically protected by the wildcard Access Application. Just:

1. Add the service to `tunnel.tf` (ingress rule)
2. Add DNS record in `dns.tf`
3. Apply Terraform changes

### Adding a New Bypass Service

To add a service that should NOT require authentication:

```hcl
# In access.tf
resource "cloudflare_zero_trust_access_application" "myservice_bypass" {
  account_id       = var.account_id
  name             = "My Service (Bypass)"
  domain           = "myservice.home-server.me"
  type             = "self_hosted"
  session_duration = "24h"

  allow_authenticate_via_warp = false
  app_launcher_visible        = false

  policies = [{
    name       = "Bypass - Allow Everyone"
    decision   = "bypass"
    precedence = 1
    include = [{
      everyone = {}
    }]
  }]
}
```

### Troubleshooting Access Issues

**"Access Denied" after login:**
- Verify your email is in the authorized users group in `access.tf`
- Check that you're logging in with the correct Google account

**Redirect loop:**
- Clear browser cookies for `home-server.me` and `cloudflareaccess.com`
- Check Cloudflare Zero Trust dashboard for policy conflicts

**Service not protected:**
- Ensure the domain matches the wildcard pattern
- Bypass applications take precedence over wildcard — check for conflicting bypass rules

**Google login not appearing:**
- Verify Google OAuth credentials in `terraform.tfvars`
- Check Google Cloud Console for OAuth consent screen configuration
- Ensure redirect URI matches exactly: `https://pcrinus.cloudflareaccess.com/cdn-cgi/access/callback`

## ⚠️ Important Notes

### Sensitive Files (Do NOT commit)
- `terraform.tfvars` - Contains zone/account IDs
- `tunnel-token` - Tunnel authentication token
- `.terraform/` - Provider binaries

> **Note**: `terraform.tfstate` is stored remotely in R2, not locally.

### GitHub Secrets Required
For CI/CD deployment via GitHub Actions:
- `CLOUDFLARE_API_TOKEN` - Terraform API token
- `CLOUDFLARE_TUNNEL_TOKEN` - Base64 encoded tunnel token (contents of `tunnel-token` file)
- `CLOUDFLARE_GOOGLE_OAUTH_CLIENT_SECRET` - Google OAuth client secret for Zero Trust Access
- `TS_AUTHKEY` - Tailscale auth key
- `SSH_PRIVATE_KEY` - SSH key for deployment
- `SSH_USER` - SSH username for deployment

### GitHub Variables Required
- `CLOUDFLARE_ZONE_ID` - Cloudflare zone ID
- `CLOUDFLARE_ACCOUNT_ID` - Cloudflare account ID
- `CLOUDFLARE_GOOGLE_OAUTH_CLIENT_ID` - Google OAuth client ID for Zero Trust Access

### Zone Settings Warning
Zone settings (TLS 1.3, SSL, HTTPS rewrites) cannot be destroyed via Terraform. They must be manually disabled in the Cloudflare dashboard if needed.

### State Management
- State is stored remotely in **Cloudflare R2** bucket: `homelab-terraform-state`
- State path: `cloudflare-tunnel/terraform.tfstate`
- R2 provides S3-compatible storage with automatic encryption
- No local state files needed — Terraform reads/writes directly from R2
- Requires `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables (R2 API credentials)

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
- [Cloudflare Zero Trust Access](https://developers.cloudflare.com/cloudflare-one/policies/access/)
- [Zero Trust Access Applications](https://developers.cloudflare.com/cloudflare-one/applications/)
- [cf-terraforming GitHub](https://github.com/cloudflare/cf-terraforming)
- [Terraform Best Practices](https://developers.cloudflare.com/terraform/advanced-topics/best-practices/)
- [Google OAuth Setup Guide](https://developers.cloudflare.com/cloudflare-one/identity/idp-integration/google/)
