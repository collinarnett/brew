{ config, lib, ... }:
let
  cfg = config.brew.btop;
  user = config.brew.user;
in
{
  options.brew.btop.enable = lib.mkEnableOption "btop" // {
    default = true;
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.btop = {
        enable = true;
        settings = {
          color_theme = "dracula";
        };
      };
    };
  };
}
