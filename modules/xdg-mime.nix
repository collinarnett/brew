{ ... }:
{
  flake.nixosModules.xdg-mime =
    { config, lib, ... }:
    let
      cfg = config.brew.xdg-mime;
      user = config.brew.user;
    in
    {
      options.brew.xdg-mime.enable = lib.mkEnableOption "xdg-mime";
      config = lib.mkIf cfg.enable {
        home-manager.users.${user} = {
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
    };
}
