{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.brew.xdg-portal;
in
{
  options.brew.xdg-portal.enable = lib.mkEnableOption "xdg-portal";
  config = lib.mkIf cfg.enable {
    xdg.portal = {
      enable = true;
      xdgOpenUsePortal = false;
      config.sway.default = lib.mkForce [
        "wlr"
        "gtk"
      ];
      extraPortals = with pkgs; [
        xdg-desktop-portal-wlr
        xdg-desktop-portal-gtk
      ];
    };
  };
}
