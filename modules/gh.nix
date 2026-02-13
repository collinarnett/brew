{ config, lib, ... }:
let
  cfg = config.brew.gh;
  user = config.brew.user;
in
{
  options.brew.gh.enable = lib.mkEnableOption "gh";
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.gh = {
        enable = true;
      };
    };
  };
}
