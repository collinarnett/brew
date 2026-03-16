{ ... }:
{
  flake.modules.homeManager.xdg-mime =
    { config, lib, ... }:
    let
      cfg = config.brew.xdg-mime;
    in
    {
      options.brew.xdg-mime.enable = lib.mkEnableOption "xdg-mime";
      config = lib.mkIf cfg.enable {
        xdg.mimeApps = {
          enable = true;
          defaultApplications = {
            "x-scheme-handler/http" = "firefox-esr.desktop";
            "x-scheme-handler/https" = "firefox-esr.desktop";
            "text/html" = "firefox-esr.desktop";
          };
        };
      };
    };
}
