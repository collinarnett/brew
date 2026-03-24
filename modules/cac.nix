{ ... }:
{
  flake.modules.nixos.cac =
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

        # Register OpenSC with p11-kit so any app using p11-kit-proxy
        # picks up the CAC module via /etc/pkcs11/modules/.
        environment.etc."pkcs11/modules/opensc-pkcs11".text = ''
          module: ${pkgs.opensc}/lib/opensc-pkcs11.so
        '';

        # Firefox reads p11-kit-proxy automatically — declarative PKCS#11 registration.
        programs.firefox.policies = {
          SecurityDevices = {
            Add = {
              "CAC" = "${pkgs.opensc}/lib/opensc-pkcs11.so";
            };
          };
        };

        home-manager.sharedModules = [
          { brew.cac.enable = true; }
        ];
      };
    };

  flake.modules.homeManager.cac =
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
        # Chrome uses a per-user NSS database (~/.pki/nssdb) and does not read
        # /etc/pkcs11/modules/ directly. Register p11-kit-proxy there once so
        # Chrome can reach OpenSC through the system-wide module config above.
        # The modutil call is skipped if the module is already registered.
        home.activation.setupChromiumCac = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          NSSDB="$HOME/.pki/nssdb"
          if [ ! -f "$NSSDB/cert9.db" ]; then
            $DRY_RUN_CMD mkdir -p "$NSSDB"
            $DRY_RUN_CMD ${pkgs.nssTools}/bin/certutil \
              -d sql:"$NSSDB" -N --empty-password
          fi
          if ! ${pkgs.nssTools}/bin/modutil -dbdir sql:"$NSSDB" -list 2>/dev/null \
              | grep -q "p11-kit-proxy"; then
            $DRY_RUN_CMD ${pkgs.nssTools}/bin/modutil \
              -force \
              -dbdir sql:"$NSSDB" \
              -add "p11-kit-proxy" \
              -libfile ${pkgs.p11-kit}/lib/p11-kit-proxy.so
          fi
        '';
      };
    };
}
