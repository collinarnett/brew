{ config, lib, ... }:
let
  cfg = config.brew.wofi;
  user = config.brew.user;
in
{
  options.brew.wofi.enable = lib.mkEnableOption "wofi";
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.wofi = {
        enable = true;
        style = builtins.readFile ./style.css;
        settings = {
          show = "run";
        };
      };
    };
  };
}
