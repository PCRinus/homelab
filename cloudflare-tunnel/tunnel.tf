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
      hostname = "plex.home-server.me"
      originRequest = {
        # Keep connections alive longer for sustained video streaming (default: 90s)
        keepAliveTimeout = "600s"
        # Allow more concurrent keep-alive connections per stream (default: 100)
        keepAliveConnections = 256
        # Generous connect timeout for initial connection setup (default: 30s)
        connectTimeout = "30s"
        # Disable chunked encoding to improve streaming throughput
        # Plex sends known content lengths; chunked encoding adds overhead
        disableChunkedEncoding = true
        # Plex origin is HTTP, no TLS to verify
        noTLSVerify = false
      }
      service = "http://plex:32400"
      }, {
      hostname      = "seerr.home-server.me"
      originRequest = {}
      service       = "http://seerr:5055"
      }, {
      hostname      = "sonarr.home-server.me"
      originRequest = {}
      service       = "http://sonarr:8989"
      }, {
      hostname      = "sonarr-anime.home-server.me"
      originRequest = {}
      service       = "http://sonarr-anime:8989"
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

