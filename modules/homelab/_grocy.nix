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
      nginx.enableSSL = true;
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
        Setting('REVERSE_PROXY_AUTH_HEADER', 'X-User');
        DefaultUserSetting('night_mode', 'off');
      '';
    };

    # Grocy runs inside this nginx as php-fpm rather than behind a proxy
    # pass, so the oauth2-proxy identity has to reach PHP as a fastcgi
    # param: derive it from the auth_request subrequest and override
    # whatever X-User header the client sent.
    services.nginx.virtualHosts."grocy.trexd.dev" = {
      # DNS-01 through the acme defaults; HTTP-01 cannot reach this host.
      acmeRoot = null;
      locations."~ \\.php$".extraConfig = lib.mkAfter ''
        auth_request_set $user $upstream_http_x_auth_request_user;
        fastcgi_param HTTP_X_USER $user;
      '';

      # The API authenticates with the GROCY-API-KEY header instead of a
      # session, and internal rewrites into the shared php location would
      # re-enter auth_request, so this location terminates the request
      # with fastcgi directly.
      locations."^~ /api" = {
        priority = 400;
        extraConfig = ''
          auth_request off;
          include ${config.services.nginx.package}/conf/fastcgi.conf;
          include ${config.services.nginx.package}/conf/fastcgi_params;
          fastcgi_param SCRIPT_NAME /index.php;
          fastcgi_param SCRIPT_FILENAME ${config.services.grocy.package}/public/index.php;
          fastcgi_param HTTP_X_USER "";
          fastcgi_pass unix:${config.services.phpfpm.pools.grocy.socket};
        '';
      };
    };
  };
}
