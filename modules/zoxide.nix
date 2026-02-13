{ config, lib, ... }:
let
  cfg = config.brew.zoxide;
  user = config.brew.user;
in
{
  options.brew.zoxide.enable = lib.mkEnableOption "zoxide";
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.zoxide = {
        enable = true;
        enableZshIntegration = true;
      };
    };
  };
}
