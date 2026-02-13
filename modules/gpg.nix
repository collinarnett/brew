{ config, lib, ... }:
let
  cfg = config.brew.gpg;
  user = config.brew.user;
in
{
  options.brew.gpg.enable = lib.mkEnableOption "gpg" // {
    default = true;
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.gpg = {
        enable = true;
        settings = {
          use-agent = true;
          pinentry-mode = "ask";
        };
      };
    };
  };
}
