{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.brew.homelab;
  host = "monica.${cfg.domain}";
in
{
  config = mkIf (cfg.enable && cfg.monica.enable) {
    # Laravel reads a base64-prefixed APP_KEY as 32 raw bytes; a bare
    # base64 string would be taken as 44 bytes and refused by its cipher.
    clan.core.vars.generators.monica_app_key = {
      files.monica_app_key.owner = config.services.monica.user;
      runtimeInputs = [ pkgs.coreutils ];
      script = ''
        printf 'base64:%s' "$(head -c 32 /dev/urandom | base64 --wrap=0)" > "$out"/monica_app_key
      '';
    };

    services.monica = {
      enable = true;
      hostname = host;
      appKeyFile = config.clan.core.vars.generators.monica_app_key.files.monica_app_key.path;
      database.createLocally = true;
      # The one account is created with `monica account:create`; it signs in
      # through kanidm from then on.
      config.APP_DISABLE_SIGNUP = true;
      nginx = {
        forceSSL = true;
        enableACME = true;
        # DNS-01 through the acme defaults; HTTP-01 cannot reach this host.
        acmeRoot = null;
      };
    };

    # The CRM's contents cannot be recreated, so a nightly dump lands in
    # the backed-up tier ahead of the restic job that ships it off-site.
    services.mysqlBackup = {
      enable = true;
      databases = [ config.services.monica.database.name ];
      calendar = "*-*-* 01:20:00";
    };

    # The patched package signs in the Monica user whose address it is given.
    # oauth2-proxy identifies people by kanidm username, so each provisioned
    # person's username maps to their first kanidm mail address.
    services.nginx.appendHttpConfig = ''
      map $monica_proxy_username $monica_proxy_email {
        default "";
      ${
        lib.concatStrings (
          lib.mapAttrsToList (
            name: person:
            lib.optionalString (
              person.mailAddresses != [ ]
            ) "  ${name} ${builtins.head person.mailAddresses};\n"
          ) config.services.kanidm.provision.persons
        )
      }}
    '';

    # Only a FastCGI parameter carries that address: client headers reach PHP
    # solely as HTTP_* parameters, so no request can supply it itself. A
    # location that sets any fastcgi_param inherits none from above, so the
    # standard ones are included here too.
    services.nginx.virtualHosts.${host}.locations = {
      "~ \\.php$".extraConfig = lib.mkAfter ''
        include ${config.services.nginx.package}/conf/fastcgi.conf;
        include ${config.services.nginx.package}/conf/fastcgi_params;
        auth_request_set $monica_proxy_username $upstream_http_x_auth_request_preferred_username;
        fastcgi_param MONICA_PROXY_EMAIL $monica_proxy_email;
      '';

      # The API authenticates with personal access tokens instead of the
      # forward-auth session, and an internal rewrite into the php location
      # would re-enter auth_request, so this location hands the request to
      # php-fpm itself.
      "^~ /api" = {
        priority = 400;
        extraConfig = ''
          auth_request off;
          include ${config.services.nginx.package}/conf/fastcgi.conf;
          include ${config.services.nginx.package}/conf/fastcgi_params;
          fastcgi_param SCRIPT_NAME /index.php;
          fastcgi_param SCRIPT_FILENAME $document_root/index.php;
          fastcgi_pass unix:${config.services.phpfpm.pools.monica.socket};
        '';
      };
    };

    services.oauth2-proxy.nginx.virtualHosts.${host} = { };
  };
}
