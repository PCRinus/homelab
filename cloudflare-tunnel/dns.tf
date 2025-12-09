resource "cloudflare_dns_record" "terraform_managed_resource_27b84829b17fbafb6c98ad518331a208_0" {
  comment  = "Domain verification record"
  content  = "203.0.113.10"
  name     = "www.home-server.me"
  proxied  = true
  tags     = []
  ttl      = 1
  type     = "A"
  zone_id  = "97c1a5749e2e19a69ae4132f95f633cd"
  settings = {}
}

resource "cloudflare_dns_record" "terraform_managed_resource_8f22cd35e6f3cc9e39ccd94b2a949363_1" {
  content = "0ba69785-f553-4e75-ae68-1f3f990e573d.cfargotunnel.com"
  name    = "ha.home-server.me"
  proxied = true
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "97c1a5749e2e19a69ae4132f95f633cd"
  settings = {
    flatten_cname = false
  }
}

resource "cloudflare_dns_record" "homepage" {
  content = "0ba69785-f553-4e75-ae68-1f3f990e573d.cfargotunnel.com"
  name    = "home-server.me"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.zone_id
  comment = "Homepage dashboard on root domain"
}

resource "cloudflare_dns_record" "terraform_managed_resource_2ed691eb805ce7bcc49600fd0424f935_3" {
  content = "0ba69785-f553-4e75-ae68-1f3f990e573d.cfargotunnel.com"
  name    = "plex.home-server.me"
  proxied = true
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "97c1a5749e2e19a69ae4132f95f633cd"
  settings = {
    flatten_cname = false
  }
}

resource "cloudflare_dns_record" "dozzle" {
  content = "0ba69785-f553-4e75-ae68-1f3f990e573d.cfargotunnel.com"
  name    = "dozzle"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.zone_id
  comment = "Dozzle Docker logs viewer"
}

resource "cloudflare_dns_record" "gatus" {
  content = "0ba69785-f553-4e75-ae68-1f3f990e573d.cfargotunnel.com"
  name    = "gatus"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.zone_id
  comment = "Gatus health monitoring"
}

resource "cloudflare_dns_record" "overseerr" {
  content = "0ba69785-f553-4e75-ae68-1f3f990e573d.cfargotunnel.com"
  name    = "overseerr"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.zone_id
  comment = "Overseerr media request service"
}

resource "cloudflare_dns_record" "sonarr" {
  content = "0ba69785-f553-4e75-ae68-1f3f990e573d.cfargotunnel.com"
  name    = "sonarr"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.zone_id
  comment = "Sonarr TV series management"
}

resource "cloudflare_dns_record" "radarr" {
  content = "0ba69785-f553-4e75-ae68-1f3f990e573d.cfargotunnel.com"
  name    = "radarr"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.zone_id
  comment = "Radarr movie management"
}

resource "cloudflare_dns_record" "prowlarr" {
  content = "0ba69785-f553-4e75-ae68-1f3f990e573d.cfargotunnel.com"
  name    = "prowlarr"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.zone_id
  comment = "Prowlarr indexer manager"
}

resource "cloudflare_dns_record" "qbittorrent" {
  content = "0ba69785-f553-4e75-ae68-1f3f990e573d.cfargotunnel.com"
  name    = "qbittorrent"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.zone_id
  comment = "qBittorrent torrent client (with built-in VPN)"
}

resource "cloudflare_dns_record" "bazarr" {
  content = "0ba69785-f553-4e75-ae68-1f3f990e573d.cfargotunnel.com"
  name    = "bazarr"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.zone_id
  comment = "Bazarr subtitle management"
}

resource "cloudflare_dns_record" "flaresolverr" {
  content = "0ba69785-f553-4e75-ae68-1f3f990e573d.cfargotunnel.com"
  name    = "flaresolverr"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.zone_id
  comment = "FlareSolverr Cloudflare bypass"
}

resource "cloudflare_dns_record" "jellyfin" {
  content = "0ba69785-f553-4e75-ae68-1f3f990e573d.cfargotunnel.com"
  name    = "jellyfin"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.zone_id
  comment = "Jellyfin media server"
}
