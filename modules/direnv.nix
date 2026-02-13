{ config, lib, ... }:
let
  cfg = config.brew.direnv;
  user = config.brew.user;
in
{
  options.brew.direnv.enable = lib.mkEnableOption "direnv" // {
    default = true;
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.direnv = {
        enable = true;
        enableZshIntegration = true;
        nix-direnv.enable = true;
      };
    };
  };
}
