{ config, ... }: {
  services.traefik = {
    enable = true;
    staticConfigOptions = {
      entryPoints = {
        web.address = ":80";
        websecure.address = ":443";
        websecure.http.tls.certResolver = "letsencrypt";
      };
      certificatesResolvers.letsencrypt.acme = {
        email = "collin@arnett.it";
        storage = "/var/lib/traefik/acme.json";
        dnsChallenge = { provider = "route53"; };
      };
      log = {
        filePath = "/var/lib/traefik/traefik.log";
        level = "DEBUG";
      };
    };
    dynamicConfigOptions = {
      http.middlewares.redirect-to-https.redirectscheme = {
        scheme = "https";
        permanent = true;
      };
      http.routers.searx = {
        rule = "Host(`search.trexd.dev`)";
        entryPoints = [ "websecure" ];
        tls.certresolver = "letsencrypt";
        service = "searx";
      };
      http.services.searx.loadBalancer.servers =
        [{ url = "http://127.0.0.1:8888"; }];
    };
  };

  systemd.services.traefik.environment = {
    AWS_PROFILE = "default";
    AWS_REGION = "us-east-1";
    AWS_SHARED_CREDENTIALS_FILE = config.sops.secrets.awscli2-credentials.path;
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
