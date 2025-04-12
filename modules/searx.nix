{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.services.homelab;
in
{
  services.searx = {
    enable = cfg.searx.enable;
    settings = {
      server.port = 8080;
      server.secret_key = "@SEARX_SECRET_KEY@";
      ui.infinite_scroll = true;
      search = {
        autocomplete = "google";
        autocomplete_min = 3;
      };
    };
  };
  systemd.services.searx.environment = mkIf cfg.searx.enable {
    SEARX_SECRET_KEY = "$(cat ${config.sops.secrets.searx_secret_key.path})";
  };
}
