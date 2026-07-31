{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.brew.homelab;
in
{
  config = mkIf (cfg.enable && cfg.rqbit.enable) {
    services.rqbit = {
      enable = true;
      # Bind to loopback only; public access is mediated by nginx.
      httpHost = "127.0.0.1";
      httpPort = 3030;
      # Run under the shared multimedia group so downloaded files are readable
      # by Jellyfin and by collin for beets imports, matching the /media model.
      group = "multimedia";
    };

    services.nginx.virtualHosts."torrents.trexd.dev" = {
      enableACME = true;
      # DNS-01 through the acme defaults; HTTP-01 cannot reach this host.
      acmeRoot = null;
      forceSSL = true;
      # rqbit serves its web UI under /web/; the API lives at the root, so
      # send a bare visit to the UI rather than the raw JSON endpoint listing.
      locations."= /".return = "302 /web/";
      locations."/".proxyPass = "http://127.0.0.1:3030";
    };
  };
}
