{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.brew.cac;
in
{
  options.brew.cac = {
    enable = lib.mkEnableOption "CAC service";
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.allowUnfreePredicate =
      pkg:
      builtins.elem (lib.getName pkg) [
        "appgate-sdp"
      ];

    services.pcscd.enable = true;

    # Allow pcscd access from remote sessions (SSH/waypipe)
    # Without this, polkit rejects smart card access for non-local sessions
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if ((action.id == "org.debian.pcsc-lite.access_pcsc" ||
             action.id == "org.debian.pcsc-lite.access_card") &&
            subject.isInGroup("wheel")) {
          return polkit.Result.YES;
        }
      });
    '';

    security.pam.p11.enable = true;
    security.pki.certificateFiles = [
      "${pkgs.dod-certs}/dod-certs.pem"
    ];

    programs.appgate-sdp.enable = true;

    programs.firefox.policies = {
      SecurityDevices = {
        Add = {
          "CAC" = "${pkgs.opensc}/lib/opensc-pkcs11.so";
        };
      };
    };
  };
}
