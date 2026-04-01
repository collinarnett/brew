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
  config = mkIf (cfg.enable && cfg.grocy.enable) {
    services.grocy = {
      enable = true;
      hostName = "grocy.trexd.dev";
      nginx.enableSSL = false;
      settings = {
        currency = "USD";
        culture = "en";
        calendar.firstDayOfWeek = 0;
        entryPage = "stock";
      };
      extraConfig = ''
        Setting('FEATURE_FLAG_CHORES', false);
        Setting('FEATURE_FLAG_TASKS', false);
        Setting('FEATURE_FLAG_BATTERIES', false);
        Setting('FEATURE_FLAG_EQUIPMENT', false);
        Setting('AUTH_CLASS', 'Grocy\Middleware\ReverseProxyAuthMiddleware');
        Setting('REVERSE_PROXY_AUTH_HEADER', 'Remote-User');
        DefaultUserSetting('night_mode', 'off');
      '';
    };

    # Grocy's NixOS module bundles nginx+php-fpm. Bind the virtualHost to
    # localhost only so Traefik can front it with TLS and Authelia.
    services.nginx.virtualHosts."grocy.trexd.dev" = {
      listen = [
        {
          addr = "127.0.0.1";
          port = 8099;
        }
      ];
    };
  };
}
