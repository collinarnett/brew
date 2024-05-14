{config, ...}: {
  users.groups.aws = {};
  users.users.traefik.extraGroups = ["aws"];
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
      http.middlewares.authelia = {
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

      http.routers.authelia = {
        rule = "Host(`login.trexd.dev`)";
        entryPoints = ["websecure"];
        tls.certResolver = "letsencrypt";
        service = "authelia";
      };
      http.services.authelia.loadBalancer.servers = [{url = "http://127.0.0.1:9091";}];

      http.routers.searx = {
        rule = "Host(`search.trexd.dev`)";
        entryPoints = ["websecure"];
        tls.certResolver = "letsencrypt";
        service = "searx";
        middlewares = "authelia";
      };
      http.services.searx.loadBalancer.servers = [{url = "http://127.0.0.1:8080";}];

      http.routers.jellyfin = {
        rule = "Host(`jellyfin.trexd.dev`)";
        entryPoints = ["websecure"];
        tls.certResolver = "letsencrypt";
        service = "jellyfin";
        middlewares = "authelia";
      };
      http.services.jellyfin.loadBalancer.servers = [{url = "http://127.0.0.1:8096";}];
    };
  };

  systemd.services.traefik.environment = {
    AWS_PROFILE = "default";
    AWS_REGION = "us-east-1";
    AWS_SHARED_CREDENTIALS_FILE = config.sops.secrets.awscli2-credentials.path;
  };

  networking.firewall.allowedTCPPorts = [80 443];
}
