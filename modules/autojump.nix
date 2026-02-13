{ config, lib, ... }:
let
  cfg = config.brew.autojump;
  user = config.brew.user;
in
{
  options.brew.autojump.enable = lib.mkEnableOption "autojump";
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.autojump = {
        enable = true;
        enableZshIntegration = true;
      };
    };
  };
}
