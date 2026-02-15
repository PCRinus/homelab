// Rewrite service URLs when accessed via Cloudflare tunnel
(function () {
  // Only run if accessed via home-server.me (Cloudflare tunnel)
  if (window.location.hostname === 'home-server.me') {
    // Port-to-subdomain mapping (hostname-agnostic)
    const portMappings = {
      // Media Management
      '32400': 'plex.home-server.me',
      '5055': 'seerr.home-server.me',
      '8989': 'sonarr.home-server.me',
      '8990': 'sonarr-anime.home-server.me',
      '7878': 'radarr.home-server.me',
      '9696': 'prowlarr.home-server.me',
      '8080': 'qbittorrent.home-server.me',
      '6767': 'bazarr.home-server.me',
      '8181': 'tautulli.home-server.me',
      '8191': 'flaresolverr.home-server.me',
      // Infrastructure
      '8081': 'dozzle.home-server.me',
      '8082': 'gatus.home-server.me',
      '3000': 'home-server.me',
      // Home Automation
      '8123': 'ha.home-server.me'
    };

    // Function to rewrite URLs in links
    function rewriteLinks() {
      document.querySelectorAll('a[href^="http://"]').forEach(link => {
        try {
          const url = new URL(link.href);
          // Skip if already pointing to a Cloudflare tunnel URL
          if (url.hostname.endsWith('home-server.me')) return;
          // Match by port number regardless of hostname
          if (url.port && portMappings[url.port]) {
            link.href = `https://${portMappings[url.port]}${url.pathname}${url.search}${url.hash}`;
          }
        } catch (e) {
          // Ignore malformed URLs
        }
      });
    }

    // Run immediately
    rewriteLinks();

    // Run again after DOM changes (for dynamically loaded content)
    const observer = new MutationObserver(rewriteLinks);
    observer.observe(document.body, {
      childList: true,
      subtree: true
    });
  }
})();
