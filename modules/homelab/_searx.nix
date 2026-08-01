{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.brew.homelab;
in
{
  config = mkIf (cfg.enable && cfg.searx.enable) {
    clan.core.vars.generators.searx_environment = {
      files.searx_environment = { };
      runtimeInputs = [ pkgs.coreutils ];
      script = ''
        printf 'SEARX_SECRET_KEY=%s\n' \
          "$(head -c 48 /dev/urandom | base64 --wrap=0 | tr -d '+/=')" \
          > "$out"/searx_environment
      '';
    };

    services.nginx.virtualHosts."search.${cfg.domain}" = {
      enableACME = true;
      # DNS-01 through the acme defaults; HTTP-01 cannot reach this host.
      acmeRoot = null;
      forceSSL = true;
      locations."/".proxyPass =
        "http://${config.services.searx.settings.server.bind_address}:${toString config.services.searx.settings.server.port}";
    };

    services.searx = {
      enable = true;
      environmentFile = config.clan.core.vars.generators.searx_environment.files.searx_environment.path;
      settings = {
        server.bind_address = "127.0.0.1";
        server.port = 8080;
        server.secret_key = "$SEARX_SECRET_KEY";
        ui.infinite_scroll = true;
        search = {
          autocomplete = "google";
          autocomplete_min = 3;
        };
      };
    };
  };
}
