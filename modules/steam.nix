{ config, lib, ... }:
let
  cfg = config.brew.steam;
in
{
  options.brew.steam.enable = lib.mkEnableOption "steam";
  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      protontricks.enable = true;
      gamescopeSession.enable = true;
      extest.enable = true;
    };

    hardware.xpadneo.enable = true;
    hardware.steam-hardware.enable = true;
  };
}
