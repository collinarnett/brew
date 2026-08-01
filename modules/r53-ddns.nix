{ ... }:
{
  flake.modules.nixos.r53-ddns =
    {
      config,
      lib,
      ...
    }:
    let
      inherit (lib)
        mkIf
        mkEnableOption
        mkOption
        types
        ;
      cfg = config.brew.r53-ddns;
    in
    {
      options.brew.r53-ddns = {
        enable = mkEnableOption "r53-ddns";
        hostname = mkOption {
          type = types.str;
          example = "ygg";
          description = ''
            Record name within the zone, without the domain. Its A
            record tracks this machine's public IPv4 address.
          '';
        };
        domain = mkOption {
          type = types.str;
          example = "example.com";
          description = "Domain of the Route53 zone.";
        };
        zoneId = mkOption {
          type = types.str;
          example = "Z02841443N2C1YNW3LDOS";
          description = "Identifier of the Route53 hosted zone.";
        };
      };

      config = mkIf cfg.enable {
        # The IAM user behind these credentials may only UPSERT the one
        # A record named below, so a leak from this machine cannot touch
        # anything else in the account.
        clan.core.vars.generators.r53-ddns = {
          files.environment = { };
          prompts.environment = {
            description = ''
              EnvironmentFile holding AWS_REGION, AWS_ACCESS_KEY_ID and
              AWS_SECRET_ACCESS_KEY for the Route53 record updater
            '';
            type = "multiline";
            persist = true;
          };
        };

        services.r53-ddns = {
          enable = true;
          inherit (cfg) hostname domain;
          zoneID = cfg.zoneId;
          ttl = 300;
          interval = "15min";
          environmentFile = config.clan.core.vars.generators.r53-ddns.files.environment.path;
        };

        # r53-ddns publishes a record for every address family it can
        # reach the internet on. Only the IPv4 address is forwarded to
        # this machine, so withholding IPv6 sockets keeps it from
        # advertising an AAAA that nothing answers on.
        systemd.services.r53-ddns.serviceConfig.RestrictAddressFamilies = [
          "AF_INET"
          "AF_NETLINK"
          "AF_UNIX"
        ];
      };
    };
}
