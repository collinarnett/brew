{ pkgs, lib, ... }:
{
  xdg.mime = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "text/html" = "firefox.desktop";
    };
  };
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    config.sway.default = lib.mkForce ["wlr" "gtk"];
    extraPortals = with pkgs; [
      xdg-desktop-portal-wlr
      xdg-desktop-portal-gtk
    ];
  };
}
