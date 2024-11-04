{
  config,
  lib,
  ...
}: let
  inherit (lib) mkIf;
  cfg = config.services.homelab;
in {
  services.calibre-web = {
    enable = cfg.calibre-web.enable;
    listen.ip = "127.0.0.1";
    options.enableBookUploading = true;
    options.calibreLibrary = "/media/books";
    options.reverseProxyAuth = {
      enable = true;
      header = "Remote-User";
    };
  };
  users.users.calibre-web.extraGroups = mkIf cfg.calibre-web.enable ["multimedia"];
}
