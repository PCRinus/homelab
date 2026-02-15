terraform {
  backend "s3" {
    bucket                      = "homelab-terraform-state"
    key                         = "cloudflare-tunnel/terraform.tfstate"
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
    endpoints = {
      s3 = "https://ed6d4bb3828b44b941ccbbd0dc250af7.eu.r2.cloudflarestorage.com"
    }
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5"
    }
  }
}

# This provider block is required to init the Cloudflare provider
# It will read credentials from environment variables
# https://developers.cloudflare.com/terraform/tutorial/track-history/
provider "cloudflare" {
}

moved {
  from = cloudflare_dns_record.overseerr
  to   = cloudflare_dns_record.seerr
}

variable "zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
  sensitive   = true
}

variable "account_id" {
  description = "Cloudflare Account ID"
  type        = string
  sensitive   = true
}

variable "domain" {
  description = "Domain name"
  type        = string
  default     = "home-server.me"
}

# -----------------------------------------------------------------------------
# Google OAuth Variables (for Cloudflare Access)
# -----------------------------------------------------------------------------
variable "google_oauth_client_id" {
  description = "Google OAuth Client ID for Cloudflare Access"
  type        = string
  sensitive   = true
}

variable "google_oauth_client_secret" {
  description = "Google OAuth Client Secret for Cloudflare Access"
  type        = string
  sensitive   = true
}

resource "cloudflare_dns_record" "www" {
  zone_id = var.zone_id
  name    = "www"
  content = "203.0.113.10"
  type    = "A"
  ttl     = 1
  proxied = true
  comment = "Domain verification record"
}

# Enable TLS 1.3
resource "cloudflare_zone_setting" "tls_1_3" {
  zone_id    = var.zone_id
  setting_id = "tls_1_3"
  value      = "on"
}

# Enable automatic HTTPS rewrites
resource "cloudflare_zone_setting" "automatic_https_rewrites" {
  zone_id    = var.zone_id
  setting_id = "automatic_https_rewrites"
  value      = "on"
}

# Set SSL mode to strict
resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.zone_id
  setting_id = "ssl"
  value      = "strict"
}