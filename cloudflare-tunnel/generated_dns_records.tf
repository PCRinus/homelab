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
  content = "2a32c37d-447c-4d24-9256-9deb86bc686f.cfargotunnel.com"
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

resource "cloudflare_dns_record" "terraform_managed_resource_6b1094bfea3ccf9296fbd38eab9a6265_2" {
  content = "fc1846ca-b4fa-43ba-bb54-13469ad1f9f1.cfargotunnel.com"
  name    = "home-server.me"
  proxied = true
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = "97c1a5749e2e19a69ae4132f95f633cd"
  settings = {
    flatten_cname = false
  }
}

resource "cloudflare_dns_record" "terraform_managed_resource_2ed691eb805ce7bcc49600fd0424f935_3" {
  content = "2a32c37d-447c-4d24-9256-9deb86bc686f.cfargotunnel.com"
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
  content = "2a32c37d-447c-4d24-9256-9deb86bc686f.cfargotunnel.com"
  name    = "dozzle"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.zone_id
  comment = "Dozzle Docker logs viewer"
}

resource "cloudflare_dns_record" "uptime" {
  content = "2a32c37d-447c-4d24-9256-9deb86bc686f.cfargotunnel.com"
  name    = "uptime"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.zone_id
  comment = "Uptime Kuma monitoring"
}
