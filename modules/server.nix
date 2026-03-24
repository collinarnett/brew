{ ... }:
{
  flake.modules.nixos.server =
    { config, lib, ... }:
    let
      cfg = config.brew.server;
    in
    {
      options.brew.server.enable = lib.mkEnableOption "server profile";
      config = lib.mkIf cfg.enable {
        brew = {
          apcupsd.enable = true;
          atticd.enable = true;
          docker-registry.enable = true;
          homelab.enable = true;
          restic.enable = true;
          sops.enable = true;
        };
      };
    };
}
