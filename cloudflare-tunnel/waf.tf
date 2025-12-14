# =============================================================================
# Cloudflare WAF (Web Application Firewall) Configuration
# =============================================================================
# This file configures WAF custom rules to protect homelab services.
# Rules are processed in order - first match wins.
#
# Available on Free plan: 5 custom rules, most actions except Log
# 
# Reference: https://developers.cloudflare.com/waf/custom-rules/
# Terraform docs: https://developers.cloudflare.com/terraform/additional-configurations/waf-custom-rules/
# =============================================================================

# -----------------------------------------------------------------------------
# WAF Custom Rules
# -----------------------------------------------------------------------------
# Phase: http_request_firewall_custom
# These rules run before managed rulesets and can block/challenge requests.
# -----------------------------------------------------------------------------

resource "cloudflare_ruleset" "waf_custom_rules" {
  zone_id     = var.zone_id
  name        = "Homelab WAF Custom Rules"
  description = "Custom security rules for home-server.me"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = [
    # -------------------------------------------------------------------------
    # Rule 1: Allow traffic only from allowed countries
    # -------------------------------------------------------------------------
    # Block all traffic from countries not in the allowlist.
    # This is an allowlist approach - much stricter than blocklisting.
    # Since this is a private homelab, we don't need global access.
    # 
    # Note: This also blocks search engine bots (Googlebot, Bingbot, etc.)
    # which is intentional - we don't want this site indexed.
    #
    # ISO 3166-1 alpha-2 codes: https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
    # Current allowlist: Romania, Greece, Serbia, Hungary
    # -------------------------------------------------------------------------
    {
      ref         = "allow_only_allowed_countries"
      description = "Block traffic from outside allowed countries (RO, GR, RS, HU)"
      expression  = "(not ip.src.country in {\"RO\" \"GR\" \"RS\" \"HU\"})"
      action      = "block"
    },

    # -------------------------------------------------------------------------
    # Rule 2: Challenge requests with high threat score
    # -------------------------------------------------------------------------
    # Even for Romanian IPs, challenge those with bad reputation.
    # Cloudflare assigns a threat score (0-100) based on IP reputation.
    # Score > 40 indicates known bad actors.
    # -------------------------------------------------------------------------
    {
      ref         = "challenge_high_threat_score"
      description = "Challenge requests with threat score > 40"
      expression  = "(cf.threat_score gt 40)"
      action      = "managed_challenge"
    },

    # -------------------------------------------------------------------------
    # Rule 3: Block known bad user agents
    # -------------------------------------------------------------------------
    # Block requests from common scanning tools and malicious bots.
    # These user agents are rarely used by legitimate clients.
    # -------------------------------------------------------------------------
    {
      ref         = "block_bad_user_agents"
      description = "Block malicious scanners and bad bots"
      expression  = "(http.user_agent contains \"sqlmap\") or (http.user_agent contains \"nikto\") or (http.user_agent contains \"masscan\") or (http.user_agent contains \"nmap\") or (http.user_agent contains \"zgrab\") or (http.user_agent eq \"\")"
      action      = "block"
    }
  ]
}

# -----------------------------------------------------------------------------
# Security Settings
# -----------------------------------------------------------------------------
# Additional zone-level security settings
# -----------------------------------------------------------------------------

# Security Level - determines how aggressively Cloudflare challenges visitors
# Options: "off", "essentially_off", "low", "medium", "high", "under_attack"
resource "cloudflare_zone_setting" "security_level" {
  zone_id    = var.zone_id
  setting_id = "security_level"
  value      = "medium"
}

# Browser Integrity Check - evaluates HTTP headers for threats
# Blocks requests with missing or unusual headers
resource "cloudflare_zone_setting" "browser_check" {
  zone_id    = var.zone_id
  setting_id = "browser_check"
  value      = "on"
}

# Email Obfuscation - protects email addresses from scrapers
resource "cloudflare_zone_setting" "email_obfuscation" {
  zone_id    = var.zone_id
  setting_id = "email_obfuscation"
  value      = "on"
}

# -----------------------------------------------------------------------------
# Cache Rules (for Plex compatibility)
# -----------------------------------------------------------------------------
# Disable caching for the zone to prevent issues with Plex streaming
# This is important for Direct Play seeking on iOS
# Reference: https://mythofechelon.co.uk/blog/2024/1/7/how-to-set-up-free-secure-high-quality-remote-access-for-plex
# -----------------------------------------------------------------------------

resource "cloudflare_ruleset" "cache_rules" {
  zone_id     = var.zone_id
  name        = "Homelab Cache Rules"
  description = "Cache bypass rules for media streaming"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules = [
    {
      ref         = "bypass_cache_all"
      description = "Bypass cache for all requests (required for Plex streaming)"
      expression  = "(http.host contains \"home-server.me\")"
      action      = "set_cache_settings"
      action_parameters = {
        cache = false
      }
    }
  ]
}

# Set caching level to "no query string" for Plex iOS Direct Play compatibility
resource "cloudflare_zone_setting" "cache_level" {
  zone_id    = var.zone_id
  setting_id = "cache_level"
  value      = "simplified"  # "simplified" = No Query String
}
