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
    # challenge with the shared aws credentials var.
    security.acme = {
      acceptTerms = true;
      defaults = {
        email = "collin@arnett.it";
        dnsProvider = "route53";
        environmentFile = pkgs.writeText "acme-route53-env" ''
          AWS_SHARED_CREDENTIALS_FILE=${config.clan.core.vars.generators.awscli2-credentials.files.awscli2-credentials.path}
          AWS_PROFILE=default
          AWS_REGION=us-east-1
        '';
      };
    };
    users.users.acme.extraGroups = [ "aws" ];

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
