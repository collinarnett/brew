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
    # TODO: Remove overlay once nixpkgs#494140 merges (calibre-web flask-limiter v4 fix)
    nixpkgs.overlays = [
      (final: prev: {
        calibre-web = prev.calibre-web.overridePythonAttrs (old: {
          version = "0.6.27-unstable-2026-02-22";
          src = prev.fetchFromGitHub {
            owner = "janeczku";
            repo = "calibre-web";
            rev = "5e48a64b1517574c31cf667be8c45bcd05cd0904";
            hash = "sha256-OgaU+Kj24AzalMM8dhelJz1L8akadJoJApQw3q8wbCc=";
          };
        });
      })
    ];
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
