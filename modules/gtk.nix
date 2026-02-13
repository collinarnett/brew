{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.brew.gtk;
  user = config.brew.user;
in
{
  options.brew.gtk.enable = lib.mkEnableOption "gtk";
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      gtk = {
        enable = true;
        theme = {
          name = "Dracula";
          package = pkgs.dracula-theme;
        };
        iconTheme = {
          name = "Dracula";
          package = pkgs.dracula-icon-theme;
        };
        cursorTheme = {
          name = "Bibata-Modern-Ice";
          package = pkgs.bibata-cursors;
        };
      };
      home.pointerCursor = {
        name = "Bibata-Modern-Ice";
        package = pkgs.bibata-cursors;
        gtk.enable = true;
        x11 = {
          enable = true;
          defaultCursor = "Bibata-Modern-Ice";
        };
      };
    };
  };
}
