{
  config,
  lib,
  ...
}: let
  inherit (lib) mkIf;
  cfg = config.services.homelab;
in {
  services.jellyfin.enable = cfg.jellyfin.enable;
  users.users.jellyfin.extraGroups = mkIf cfg.jellyfin.enable ["multimedia"];
}
