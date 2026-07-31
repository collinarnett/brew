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
        http.routers.searx = mkIf cfg.searx.enable {
          rule = "Host(`search.trexd.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "searx";
          middlewares = "kanidm-auth";
        };
        http.services.searx.loadBalancer.servers = mkIf cfg.searx.enable [
          { url = "http://127.0.0.1:8080"; }
        ];

        # No forward-auth: OPDS apps and the KOReader sync plugin
        # authenticate with Kavita API keys and cannot carry a session
        # cookie. Kavita's own login (OIDC against Kanidm) guards the web
        # UI and API.
        http.routers.kavita = mkIf cfg.kavita.enable {
          rule = "Host(`books.trexd.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "kavita";
        };
        http.services.kavita.loadBalancer.servers = mkIf cfg.kavita.enable [
          { url = "http://127.0.0.1:5001"; }
        ];

        http.routers.grocy = mkIf cfg.grocy.enable {
          rule = "Host(`grocy.trexd.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "grocy";
          middlewares = "kanidm-auth";
        };
        # Bypass forward-auth for Grocy API — authenticated by GROCY-API-KEY header
        http.middlewares.strip-remote-user.headers.customRequestHeaders."X-Auth-Request-Preferred-Username" =
          "";
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

        # Forward-auth through oauth2-proxy against Kanidm: the middleware
        # hits the proxy root, which 302s unauthenticated browsers into the
        # sign-in flow and answers 202 (static upstream) for valid sessions.
        # The shared /oauth2/ router serves the callback on every protected
        # domain.
        http.middlewares.kanidm-auth.forwardAuth = mkIf cfg.kanidm.enable {
          address = "http://127.0.0.1:4180";
          trustForwardHeader = true;
          authResponseHeaders = [
            "X-Auth-Request-User"
            "X-Auth-Request-Email"
            "X-Auth-Request-Preferred-Username"
          ];
        };
        http.routers.oauth2-proxy = mkIf cfg.kanidm.enable {
          rule = "(Host(`search.trexd.dev`) || Host(`grocy.trexd.dev`) || Host(`torrents.trexd.dev`) || Host(`home.trexd.dev`)) && PathPrefix(`/oauth2/`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "oauth2-proxy";
          priority = 200;
        };
        http.services.oauth2-proxy.loadBalancer.servers = mkIf cfg.kanidm.enable [
          { url = "http://127.0.0.1:4180"; }
        ];

        # Kanidm refuses plaintext HTTP, so traefik re-encrypts to the
        # backend; the transport pins the SNI since the dial address is
        # 127.0.0.1 but the backend cert is for idm.trexd.dev.
        http.serversTransports.kanidm = mkIf cfg.kanidm.enable {
          serverName = "idm.trexd.dev";
        };
        http.routers.kanidm = mkIf cfg.kanidm.enable {
          rule = "Host(`idm.trexd.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "kanidm";
        };
        http.services.kanidm.loadBalancer = mkIf cfg.kanidm.enable {
          servers = [ { url = "https://127.0.0.1:8445"; } ];
          serversTransport = "kanidm";
        };

        http.routers.homepage = mkIf cfg.homepage.enable {
          rule = "Host(`home.trexd.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "homepage";
          middlewares = "kanidm-auth";
        };
        http.services.homepage.loadBalancer.servers = mkIf cfg.homepage.enable [
          { url = "http://127.0.0.1:8082"; }
        ];

        # Auth handled inside Jellyfin by jellyfin-plugin-sso (OIDC against Kanidm).
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

        # No forward-auth on either radicle router: radicle-httpd is a
        # read-only API by design, and git/rad clients hitting /api and
        # /raw cannot carry a session cookie.
        http.routers.radicle = mkIf cfg.radicle.enable {
          rule = "Host(`garden.trexd.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "radicle";
        };
        http.services.radicle.loadBalancer.servers = mkIf cfg.radicle.enable [
          { url = "http://127.0.0.1:8779"; }
        ];
        http.routers.radicle-api = mkIf cfg.radicle.enable {
          rule = "Host(`garden.trexd.dev`) && (PathPrefix(`/api`) || PathPrefix(`/raw`))";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "radicle-api";
          priority = 100;
        };
        http.services.radicle-api.loadBalancer.servers = mkIf cfg.radicle.enable [
          { url = "http://127.0.0.1:8778"; }
        ];

        # rqbit serves its web UI under /web/; the API lives at the root, so
        # send a bare visit to the UI rather than the raw JSON endpoint listing.
        http.middlewares.rqbit-web.redirectregex = mkIf cfg.rqbit.enable {
          regex = "^https://torrents\\.trexd\\.dev/?$";
          replacement = "https://torrents.trexd.dev/web/";
        };
        http.routers.rqbit = mkIf cfg.rqbit.enable {
          rule = "Host(`torrents.trexd.dev`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
          service = "rqbit";
          middlewares = [
            "kanidm-auth"
            "rqbit-web"
          ];
        };
        http.services.rqbit.loadBalancer.servers = mkIf cfg.rqbit.enable [
          { url = "http://127.0.0.1:3030"; }
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
