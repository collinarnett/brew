{ config, lib, ... }:
let
  cfg = config.brew.atticd;
in
{
  options.brew.atticd.enable = lib.mkEnableOption "atticd";
  config = lib.mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      ensureDatabases = [ config.services.atticd.user ];
      ensureUsers = [
        {
          name = config.services.atticd.user;
          ensureDBOwnership = true;
        }
      ];
    };

    systemd.services.atticd = {
      serviceConfig.LoadCredentials = "credentials:${config.sops.secrets.attic_environment.path}";
    };

    services.atticd = {
      enable = true;
      environmentFile = config.sops.secrets.attic_environment.path;
      settings = {
        listen = "[::]:8085";

        jwt = { };

        chunking = {
          nar-size-threshold = 64 * 1024; # 64 KiB
          min-size = 16 * 1024; # 16 KiB
          avg-size = 64 * 1024; # 64 KiB
          max-size = 256 * 1024; # 256 KiB
        };
      };
    };
  };
}
