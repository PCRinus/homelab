// Rewrite service URLs when accessed via Cloudflare tunnel
(function() {
  // Only run if accessed via home-server.me (Cloudflare tunnel)
  if (window.location.hostname === 'home-server.me') {
    // Map of local URLs to Cloudflare tunnel URLs
    const urlMappings = {
      'homelab:32400': 'plex.home-server.me',
      'homelab:5055': 'overseerr.home-server.me', // Add if you create this
      'homelab:8989': 'sonarr.home-server.me',    // Add if you create this
      'homelab:7878': 'radarr.home-server.me',    // Add if you create this
      'homelab:9696': 'prowlarr.home-server.me',  // Add if you create this
      'homelab:8080': 'qbittorrent.home-server.me', // Add if you create this
      'homelab:8191': 'flaresolverr.home-server.me', // Add if you create this
      'homelab:8081': 'dozzle.home-server.me',
      'homelab:3001': 'uptime.home-server.me',
      'homelab:3000': 'home-server.me',
      'homelab:8123': 'ha.home-server.me'
    };

    // Function to rewrite URLs in links
    function rewriteLinks() {
      document.querySelectorAll('a[href^="http://homelab:"]').forEach(link => {
        const originalUrl = new URL(link.href);
        const hostPort = `${originalUrl.hostname}:${originalUrl.port}`;
        
        if (urlMappings[hostPort]) {
          // Replace with HTTPS Cloudflare tunnel URL
          link.href = `https://${urlMappings[hostPort]}${originalUrl.pathname}${originalUrl.search}${originalUrl.hash}`;
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
