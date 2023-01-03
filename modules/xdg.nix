{pkgs, ...}: {
  xdg = {
    mime = {
      enable = true;
      defaultApplications = {default-web-browser = "firefox.desktop";};
    };
    portal = {
      enable = true;
      wlr.enable = true;
      # gtk portal needed to make gtk apps happy
      extraPortals = [pkgs.xdg-desktop-portal-gtk];
    };
  };
}
