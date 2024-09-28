{pkgs, ...}: {
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

    # trace: warning: xdg-desktop-portal 1.17 reworked how portal implementations are loaded, you
    # should either set `xdg.portal.config` or `xdg.portal.configPackages`
    # to specify which portal backend to use for the requested interface.
    #
    # https://github.com/flatpak/xdg-desktop-portal/blob/1.18.1/doc/portals.conf.rst.in
    #
    # If you simply want to keep the behaviour in < 1.17, which uses the first
    # portal implementation found in lexicographical order, use the following:
    #
    # config.common.default = "*";
    config.sway.default = ["wlr" "gtk"];
    xdgOpenUsePortal = true;
    wlr.enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
    wlr.settings.screencast = {
      output_name = "DP-2";
      chooser_type = "simple";
      chooser_cmd = "${pkgs.slurp}/bin/slurp -f %o -or";
    };
    # # gtk portal needed to make gtk apps happy
    # extraPortals =
    #   let gnome = config.services.xserver.desktopManager.gnome.enable;
    #   in [ pkgs.xdg-desktop-portal-wlr ]
    #   ++ lib.optional (!gnome) pkgs.xdg-desktop-portal-gtk;
  };
}
