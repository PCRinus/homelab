resource "cloudflare_zero_trust_tunnel_cloudflared" "homeserver" {
  account_id = "ed6d4bb3828b44b941ccbbd0dc250af7"
  config_src = "cloudflare"
  name       = "homeserver"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homeserver" {
  account_id = "ed6d4bb3828b44b941ccbbd0dc250af7"
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homeserver.id
  config = {
    __configuration_flags = {
      no-autoupdate = "true"
    }
    ingress = [{
      hostname      = "home-server.me"
      originRequest = {}
      service       = "http://homepage:3000"
      }, {
      hostname      = "plex.home-server.me"
      originRequest = {}
      service       = "http://plex:32400"
      }, {
      hostname      = "jellyfin.home-server.me"
      originRequest = {}
      service       = "http://jellyfin:8096"
      }, {
      hostname      = "overseerr.home-server.me"
      originRequest = {}
      service       = "http://overseerr:5055"
      }, {
      hostname      = "sonarr.home-server.me"
      originRequest = {}
      service       = "http://sonarr:8989"
      }, {
      hostname      = "radarr.home-server.me"
      originRequest = {}
      service       = "http://radarr:7878"
      }, {
      hostname      = "prowlarr.home-server.me"
      originRequest = {}
      service       = "http://prowlarr:9696"
      }, {
      hostname      = "qbittorrent.home-server.me"
      originRequest = {}
      service       = "http://qbittorrent:8080"
      }, {
      hostname      = "bazarr.home-server.me"
      originRequest = {}
      service       = "http://bazarr:6767"
      }, {
      hostname      = "tautulli.home-server.me"
      originRequest = {}
      service       = "http://tautulli:8181"
      }, {
      hostname      = "flaresolverr.home-server.me"
      originRequest = {}
      service       = "http://flaresolverr:8191"
      }, {
      hostname      = "ha.home-server.me"
      originRequest = {}
      service       = "http://homeassistant:8123"
      }, {
      hostname      = "dozzle.home-server.me"
      originRequest = {}
      service       = "http://dozzle:8080"
      }, {
      hostname      = "gatus.home-server.me"
      originRequest = {}
      service       = "http://gatus:8080"
      }, {
      originRequest = {}
      service       = "http_status:404"
    }]
    warp-routing = {}
  }
}

