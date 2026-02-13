{ config, lib, ... }:
let
  cfg = config.brew.bat;
  user = config.brew.user;
in
{
  options.brew.bat.enable = lib.mkEnableOption "bat";
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.bat = {
        enable = true;
        config = {
          theme = "Dracula";
        };
      };
    };
  };
}
