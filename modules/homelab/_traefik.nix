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
  config = mkIf (cfg.enable && cfg.traefik.enable) {
    users.users.traefik.extraGroups = [ "aws" ];
    services.traefik = {
      enable = true;
      staticConfigOptions = {
        entryPoints = {
          web = {
            address = ":80";
            http.redirections.entrypoint = {
              to = "websecure";
              scheme = "https";
            };
          };
          websecure = {
            address = ":443";
            forwardedHeaders = {
              trustedIPs = [
                "192.168.1.1/32"
                "127.0.0.1/32"
              ];
            };
            http.tls.certResolver = "letsencrypt";
          };
        };
        certificatesresolvers.letsencrypt.acme = {
          email = "collin@arnett.it";
          storage = "/var/lib/traefik/acme.json";
          dnsChallenge = {
            provider = "route53";
          };
        };
        log = {
          filePath = "/var/lib/traefik/traefik.log";
          level = "DEBUG";
        };
        accessLog = {
          filePath = "/var/lib/traefik/access.log";
          filters.statusCodes = [
            "302"
            "303"
          ];
        };
      };
      dynamicConfigOptions = {
        http.middlewares.authelia = mkIf cfg.authelia.enable {
          forwardauth = {
            address = "http://127.0.0.1:9091/api/verify?rd=https://login.trexd.dev/";
            trustForwardHeader = true;
            authResponseHeaders = [
              "Remote-User"
              "Remote-Name"
              "Remote-Email"
              "Remote-Groups"
            ];
          };
        };

        http.routers.authelia = mkIf cfg.authelia.enable {
          rule = "Host(`login.trexd.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "authelia";
        };
        http.services.authelia.loadBalancer.servers = mkIf cfg.authelia.enable [
          { url = "http://127.0.0.1:9091"; }
        ];

        http.routers.searx = mkIf cfg.searx.enable {
          rule = "Host(`search.trexd.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "searx";
          middlewares = "authelia";
        };
        http.services.searx.loadBalancer.servers = mkIf cfg.searx.enable [
          { url = "http://127.0.0.1:8080"; }
        ];

        http.routers.calibre-web = mkIf cfg.calibre-web.enable {
          rule = "Host(`books.trexd.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "calibre-web";
          middlewares = "authelia";
        };
        http.services.calibre-web.loadBalancer.servers = mkIf cfg.calibre-web.enable [
          { url = "http://127.0.0.1:8083"; }
        ];

        http.routers.grocy = mkIf cfg.grocy.enable {
          rule = "Host(`grocy.trexd.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "grocy";
          middlewares = "authelia";
        };
        # Bypass Authelia for Grocy API — authenticated by GROCY-API-KEY header
        http.middlewares.strip-remote-user.headers.customRequestHeaders.Remote-User = "";
        http.routers.grocy-api = mkIf cfg.grocy.enable {
          rule = "Host(`grocy.trexd.dev`) && PathPrefix(`/api`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "grocy";
          middlewares = "strip-remote-user";
          priority = 100;
        };
        http.services.grocy.loadBalancer.servers = mkIf cfg.grocy.enable [
          { url = "http://127.0.0.1:8099"; }
        ];

        # Auth handled inside Jellyfin by jellyfin-plugin-sso (OIDC against Authelia).
        # Every Jellyfin user is pinned to AuthenticationProviderId =
        # Jellyfin.Plugin.SSO_Auth.Api.SSOController, so password login is dead
        # even with the form publicly exposed. Native clients (Finamp audio
        # streams, /socket websocket) need the proxy out of the way.
        http.routers.jellyfin = mkIf cfg.jellyfin.enable {
          rule = "Host(`media.trexd.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "jellyfin";
        };
        http.services.jellyfin.loadBalancer.servers = mkIf cfg.jellyfin.enable [
          { url = "http://127.0.0.1:8096"; }
        ];
      };
    };

    systemd.services.traefik.environment = {
      AWS_PROFILE = "default";
      AWS_REGION = "us-east-1";
      AWS_SHARED_CREDENTIALS_FILE =
        config.clan.core.vars.generators.awscli2-credentials.files.awscli2-credentials.path;
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
