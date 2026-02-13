{ config, lib, ... }:
let
  cfg = config.brew.beets;
  user = config.brew.user;
in
{
  options.brew.beets.enable = lib.mkEnableOption "beets";
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.beets = {
        enable = true;
        settings = {
          directory = "/media/music/";
          plugins = [
            "fetchart"
            "musicbrainz"
          ];
        };
      };
    };
  };
}
