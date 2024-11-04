{
  config,
  lib,
  ...
}: let
  inherit (lib) mkIf;
  cfg = config.services.homelab;
in {
  users.users.traefik.extraGroups = mkIf cfg.traefik.enable ["aws"];
  services.traefik = {
    enable = cfg.traefik.enable;
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
            trustedIPs = ["192.168.1.1/32" "127.0.0.1/32"];
          };
          http.tls.certResolver = "letsencrypt";
        };
      };
      certificatesresolvers.letsencrypt.acme = {
        email = "collin@arnett.it";
        storage = "/var/lib/traefik/acme.json";
        dnsChallenge = {provider = "route53";};
      };
      log = {
        filePath = "/var/lib/traefik/traefik.log";
        level = "DEBUG";
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
        entryPoints = ["websecure"];
        tls.certResolver = "letsencrypt";
        service = "authelia";
      };
      http.services.authelia.loadBalancer.servers = mkIf cfg.authelia.enable [{url = "http://127.0.0.1:9091";}];

      http.routers.searx = mkIf cfg.searx.enable {
        rule = "Host(`search.trexd.dev`)";
        entryPoints = ["websecure"];
        tls.certResolver = "letsencrypt";
        service = "searx";
        middlewares = "authelia";
      };
      http.services.searx.loadBalancer.servers = mkIf cfg.searx.enable [{url = "http://127.0.0.1:8080";}];

      http.routers.calibre-web = mkIf cfg.calibre-web.enable {
        rule = "Host(`books.trexd.dev`)";
        entryPoints = ["websecure"];
        tls.certResolver = "letsencrypt";
        service = "calibre-web";
        middlewares = "authelia";
      };
      http.services.calibre-web.loadBalancer.servers = mkIf cfg.calibre-web.enable [{url = "http://127.0.0.1:8083";}];

      http.routers.jellyfin = mkIf cfg.jellyfin.enable {
        rule = "Host(`media.trexd.dev`)";
        entryPoints = ["websecure"];
        tls.certResolver = "letsencrypt";
        service = "jellyfin";
        middlewares = "authelia";
      };
      http.services.jellyfin.loadBalancer.servers = mkIf cfg.jellyfin.enable [{url = "http://127.0.0.1:8096";}];
    };
  };

  systemd.services.traefik.environment = mkIf cfg.traefik.enable {
    AWS_PROFILE = "default";
    AWS_REGION = "us-east-1";
    AWS_SHARED_CREDENTIALS_FILE = config.sops.secrets.awscli2-credentials.path;
  };

  networking.firewall.allowedTCPPorts = mkIf cfg.traefik.enable [80 443];
}
