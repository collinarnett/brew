{...}: {
  xdg = {
    mime = {
      enable = true;
      defaultApplications = {default-web-browser = "firefox.desktop";};
    };
    portal.config.common.default = "*";
  };
}
