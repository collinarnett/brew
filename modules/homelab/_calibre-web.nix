{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.brew.homelab;
in
{
  config = mkIf (cfg.enable && cfg.calibre-web.enable) {
    services.calibre-web = {
      enable = true;
      listen.ip = "127.0.0.1";
      options.enableBookUploading = true;
      options.calibreLibrary = "/media/books";
      options.reverseProxyAuth = {
        enable = true;
        header = "Remote-User";
      };
    };
    users.users.calibre-web.extraGroups = [ "multimedia" ];
  };
}
