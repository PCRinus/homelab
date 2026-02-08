# =============================================================================
# Cloudflare Zero Trust Access Configuration
# =============================================================================
# This file configures authentication for homelab services using Cloudflare
# Access with Google as the identity provider.
#
# Protected services require Google login (SSO across all *.home-server.me)
# Bypassed services: Plex, Homepage, Home Assistant (use their own auth)
# =============================================================================

# -----------------------------------------------------------------------------
# Google Identity Provider
# -----------------------------------------------------------------------------
resource "cloudflare_zero_trust_access_identity_provider" "google" {
  account_id = var.account_id
  name       = "Google"
  type       = "google"

  config = {
    client_id     = var.google_oauth_client_id
    client_secret = var.google_oauth_client_secret
  }
}

# -----------------------------------------------------------------------------
# Access Group - Authorized Users
# -----------------------------------------------------------------------------
# Defines who can access protected services. Add more emails here as needed.
resource "cloudflare_zero_trust_access_group" "authorized_users" {
  account_id = var.account_id
  name       = "Homelab Authorized Users"

  include = [{
    email = {
      email = "mircea.casapu@gmail.com"
    }
  }]
}

# -----------------------------------------------------------------------------
# Access Application - Protected Services (Wildcard)
# -----------------------------------------------------------------------------
# Protects all *.home-server.me subdomains by default
resource "cloudflare_zero_trust_access_application" "protected_services" {
  account_id       = var.account_id
  name             = "Homelab Protected Services"
  domain           = "*.home-server.me"
  type             = "self_hosted"
  session_duration = "168h" # 7 days

  # Require identity (no bypass by default)
  allow_authenticate_via_warp = false
  app_launcher_visible        = true

  # Inline policy - allow authorized users
  policies = [{
    name       = "Allow Authorized Users"
    decision   = "allow"
    precedence = 1
    include = [{
      group = {
        id = cloudflare_zero_trust_access_group.authorized_users.id
      }
    }]
  }]
}

# -----------------------------------------------------------------------------
# Bypass Applications - No Authentication Required
# -----------------------------------------------------------------------------

# Plex - Uses its own authentication
resource "cloudflare_zero_trust_access_application" "plex_bypass" {
  account_id       = var.account_id
  name             = "Plex (Bypass)"
  domain           = "plex.home-server.me"
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

# Homepage - Dashboard (bypass for easy access)
resource "cloudflare_zero_trust_access_application" "homepage_bypass" {
  account_id       = var.account_id
  name             = "Homepage (Bypass)"
  domain           = "home-server.me"
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

# Home Assistant - Uses its own authentication (needed for mobile app)
resource "cloudflare_zero_trust_access_application" "ha_bypass" {
  account_id       = var.account_id
  name             = "Home Assistant (Bypass)"
  domain           = "ha.home-server.me"
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

