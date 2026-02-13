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
  config = mkIf (cfg.enable && cfg.jellyfin.enable) {
    services.jellyfin.enable = true;
    users.users.jellyfin.extraGroups = [ "multimedia" ];
  };
}
