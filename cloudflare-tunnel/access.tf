# =============================================================================
# Cloudflare Zero Trust Access Configuration
# =============================================================================
# This file configures authentication for homelab services using Cloudflare
# Access with Google as the identity provider.
#
# Protected services require Google login (SSO across all *.home-server.me)
# Bypassed services: Plex, Homepage, Home Assistant (use their own auth)
# Service token only: legislation-relay (ssm-usor Worker)
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

# -----------------------------------------------------------------------------
# Legislation Relay - Service Token Only
# -----------------------------------------------------------------------------
# A Worker in another Cloudflare account fetches legislatie.just.ro through
# this host. It authenticates with the service token below; no one logs in.
resource "cloudflare_zero_trust_access_service_token" "ssm_usor_legislation" {
  account_id = var.account_id
  name       = "ssm-usor-legislation"
  duration   = "8760h"

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_zero_trust_access_application" "legislation_relay" {
  account_id       = var.account_id
  name             = "Legislation Relay (Service Token)"
  domain           = "legislation-relay.home-server.me"
  type             = "self_hosted"
  session_duration = "24h"

  allow_authenticate_via_warp = false
  app_launcher_visible        = false

  # The caller treats the portal's 302s as meaningful; a redirect to the login
  # page on a bad token would look like one of them.
  service_auth_401_redirect = true

  policies = [{
    name       = "Service Auth - ssm-usor Worker"
    decision   = "non_identity"
    precedence = 1
    include = [{
      service_token = {
        token_id = cloudflare_zero_trust_access_service_token.ssm_usor_legislation.id
      }
    }]
  }]
}

output "legislation_relay_client_id" {
  value = cloudflare_zero_trust_access_service_token.ssm_usor_legislation.client_id
}

output "legislation_relay_client_secret" {
  value     = cloudflare_zero_trust_access_service_token.ssm_usor_legislation.client_secret
  sensitive = true
}
