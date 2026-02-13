{ config, lib, ... }:
let
  cfg = config.brew.zathura;
  user = config.brew.user;
in
{
  options.brew.zathura.enable = lib.mkEnableOption "zathura";
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.zathura = {
        enable = true;
        options = {
          selection-clipboard = "clipboard";
        };
        extraConfig = builtins.readFile ./zathurarc;
      };
    };
  };
}
