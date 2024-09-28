{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.cac;
in {
  options.services.cac = {
    enable = mkEnableOption "CAC service";
  };

  config = mkIf cfg.enable {
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [
        "appgate-sdp"
      ];
    nixpkgs.overlays = [
      (final: prev: let
        inherit (prev) lib fetchurl;
      in {
        appgate-sdp =
          prev.appgate-sdp.overrideAttrs
          rec {
            version = "6.4.0";
            src = fetchurl {
              url = "https://bin.appgate-sdp.com/${lib.versions.majorMinor version}/client/appgate-sdp_${version}_amd64.deb";
              sha256 = "sha256-0h6Mz3B7fADGL5tGbrKNYpVIAvRu7Xx0n9OvjOeVCds=";
            };
          };
      })
    ];

    services.pcscd.enable = true;

    security.pam.p11.enable = true;
    security.pki.certificateFiles = ["${pkgs.dod-certs}/dod-certs.pem"];

    programs.appgate-sdp.enable = true;
    programs.firefox.policies = {
      SecurityDevices = {
        Add = {
          "CAC" = "${pkgs.cackey}/lib/libcackey.so";
        };
      };
    };
    # Must go to Firefox -> Settings -> Privacy & Security -> Security Devices
    # and select "Load" then navigate to the cackey store path and select libcackey.so
    environment.systemPackages = with pkgs; [
      cackey
    ];
  };
}
