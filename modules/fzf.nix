{ config, lib, ... }:
let
  cfg = config.brew.fzf;
  user = config.brew.user;
in
{
  options.brew.fzf.enable = lib.mkEnableOption "fzf";
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.fzf = {
        enable = true;
        enableZshIntegration = true;
      };
    };
  };
}
