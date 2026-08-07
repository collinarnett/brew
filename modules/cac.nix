{ ... }:
let
  # NSS records a PKCS#11 module's library path verbatim in each profile's
  # pkcs11.txt and dlopens it at startup. Registering this indirection keeps
  # those databases valid across p11-kit and OpenSC upgrades. It sits outside
  # /etc/pkcs11 because p11-kit scans that directory for its own configuration.
  pkcs11ProxyPath = "/etc/pkcs11-proxy/p11-kit-proxy.so";
in
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

        environment.etc."pkcs11-proxy/p11-kit-proxy.so".source = "${pkgs.p11-kit}/lib/p11-kit-proxy.so";

        # Firefox resolves the proxy to whatever /etc/pkcs11/modules/ lists, so
        # an OpenSC upgrade reaches Firefox without touching any profile.
        programs.firefox.policies = {
          SecurityDevices = {
            Add = {
              "CAC" = pkcs11ProxyPath;
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
        # /etc/pkcs11/modules/ directly. Register p11-kit-proxy there so Chrome
        # can reach OpenSC through the system-wide module config above. The
        # guard matches on the library path, so a database still holding some
        # other path is corrected rather than left alone.
        home.activation.setupChromiumCac = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          NSSDB="$HOME/.pki/nssdb"
          MODUTIL="${pkgs.nssTools}/bin/modutil"
          if [ ! -f "$NSSDB/cert9.db" ]; then
            $DRY_RUN_CMD mkdir -p "$NSSDB"
            $DRY_RUN_CMD ${pkgs.nssTools}/bin/certutil \
              -d sql:"$NSSDB" -N --empty-password
          fi
          if ! "$MODUTIL" -dbdir sql:"$NSSDB" -list 2>/dev/null \
              | grep -qF "${pkcs11ProxyPath}"; then
            $DRY_RUN_CMD "$MODUTIL" -force -dbdir sql:"$NSSDB" \
              -delete "p11-kit-proxy" >/dev/null 2>&1 || true
            $DRY_RUN_CMD "$MODUTIL" -force -dbdir sql:"$NSSDB" \
              -add "p11-kit-proxy" -libfile "${pkcs11ProxyPath}"
          fi
        '';
      };
    };
}
