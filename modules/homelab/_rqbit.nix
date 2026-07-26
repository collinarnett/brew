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
      # Bind to loopback only; public access is mediated by Traefik + Authelia.
      httpHost = "127.0.0.1";
      httpPort = 3030;
      # Run under the shared multimedia group so downloaded files are readable
      # by Jellyfin and by collin for beets imports, matching the /media model.
      group = "multimedia";
    };
  };
}
