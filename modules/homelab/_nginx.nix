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
  config = mkIf (cfg.enable && cfg.nginx.enable) {
    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
    };

    # Every vhost obtains its certificate through the route53 DNS
    # challenge with the acme-scoped aws credentials var.
    security.acme = {
      acceptTerms = true;
      defaults = {
        email = "collin@arnett.it";
        dnsProvider = "route53";
        environmentFile = pkgs.writeText "acme-route53-env" ''
          AWS_SHARED_CREDENTIALS_FILE=${config.clan.core.vars.generators.acme-aws-credentials.files.acme-aws-credentials.path}
          AWS_PROFILE=default
          AWS_REGION=us-east-1
        '';
      };
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
