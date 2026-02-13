{ config, lib, ... }:
let
  cfg = config.brew.mako;
  user = config.brew.user;
in
{
  options.brew.mako.enable = lib.mkEnableOption "mako";
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      services.mako = {
        enable = true;
        settings = {
          background-color = "#282a36";
          text-color = "#f8f8f2";
          border-color = "#282a36";
          default-timeout = 5000;
        };
        extraConfig = ''
          [urgency=low]
          border-color=#8be9fd

          [urgency=normal]
          border-color=#6272a4

          [urgency=high]
          border-color=#ff5555
        '';
      };
    };
  };
}
