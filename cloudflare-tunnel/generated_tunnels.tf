resource "cloudflare_zero_trust_tunnel_cloudflared" "terraform_managed_resource_2a32c37d-447c-4d24-9256-9deb86bc686f_0" {
  account_id = "ed6d4bb3828b44b941ccbbd0dc250af7"
  config_src = "local"
  name       = "homeserver"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "terraform_managed_resource_ed6d4bb3828b44b941ccbbd0dc250af7_0" {
  account_id = "ed6d4bb3828b44b941ccbbd0dc250af7"
  source     = "local"
  tunnel_id  = "2a32c37d-447c-4d24-9256-9deb86bc686f"
  config = {
    __configuration_flags = {
      no-autoupdate = "true"
    }
    ingress = [{
      hostname      = "home-server.me"
      originRequest = {}
      service       = "http://localhost:3000"
      }, {
      hostname      = "plex.home-server.me"
      originRequest = {}
      service       = "http://localhost:32400"
      }, {
      hostname      = "ha.home-server.me"
      originRequest = {}
      service       = "http://localhost:8123"
      }, {
      hostname      = "dozzle.home-server.me"
      originRequest = {}
      service       = "http://localhost:8081"
      }, {
      hostname      = "uptime.home-server.me"
      originRequest = {}
      service       = "http://localhost:3001"
      }, {
      originRequest = {}
      service       = "http_status:404"
    }]
    warp-routing = {}
  }
}

