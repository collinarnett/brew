{ ... }:
{
  flake.modules.homeManager.proton-mail =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.proton-mail;
      tomlFormat = pkgs.formats.toml { };
      bridgeState = "${config.xdg.dataHome}/protonmail";
      keychainHome = "${bridgeState}/keychain/gnupg";
      passwordStore = "${bridgeState}/keychain/password-store";
      mcpState = "${bridgeState}/mcp";
      keychainEnvironment = [
        "GNUPGHOME=${keychainHome}"
        "PASSWORD_STORE_DIR=${passwordStore}"
      ];
      setup = pkgs.writeShellApplication {
        name = "proton-bridge-setup";
        runtimeInputs = with pkgs; [
          coreutils
          gawk
          gnupg
          pass
          protonmail-bridge
          systemd
        ];
        text = ''
          export GNUPGHOME=${lib.escapeShellArg keychainHome}
          export PASSWORD_STORE_DIR=${lib.escapeShellArg passwordStore}
          mcp_state=${lib.escapeShellArg mcpState}
          umask 077
          mkdir -p "$GNUPGHOME" "$PASSWORD_STORE_DIR" "$mcp_state"

          systemctl --user stop protonmail-bridge.service

          # The service decrypts this key unattended, so it has no passphrase.
          # It only guards Bridge's vault key on this machine's encrypted disk.
          if [ ! -e "$PASSWORD_STORE_DIR/.gpg-id" ]; then
            gpg --batch --passphrase "" \
              --quick-generate-key "proton-bridge keychain" default default never
            fingerprint=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/ { print $10; exit }')
            pass init "$fingerprint"
          fi

          cat <<INSTRUCTIONS
          In the Bridge shell that opens next, run:

            login                      sign in, with your 2FA code
            info                       shows the IMAP username and password
            cert export                then enter $mcp_state
            updates autoupdates disable
            exit

          INSTRUCTIONS
          protonmail-bridge --cli

          rm -f "$mcp_state/key.pem"
          if [ ! -s "$mcp_state/cert.pem" ]; then
            echo "No certificate at $mcp_state/cert.pem: rerun and use cert export." >&2
            exit 1
          fi
          IFS= read -rsp "Paste the Bridge password from info: " bridge_password
          echo
          printf '%s\n' "$bridge_password" > "$mcp_state/bridge-password"

          systemctl --user start protonmail-bridge.service
          echo "Bridge is running."
        '';
      };
    in
    {
      options.brew.proton-mail = {
        enable = lib.mkEnableOption "Proton Mail Bridge and its MCP server";
        address = lib.mkOption {
          type = lib.types.str;
          description = ''
            The Proton address: the IMAP username `info` shows in Bridge and
            the From address of saved drafts.
          '';
        };
      };
      config = lib.mkIf cfg.enable {
        home.packages = [ setup ];
        services.protonmail-bridge = {
          enable = true;
          extraPackages = with pkgs; [
            gnupg
            pass
          ];
        };
        systemd.user.services.protonmail-bridge = {
          # Started without a keychain, Bridge writes its vault unencrypted.
          Unit.ConditionPathExists = "${passwordStore}/.gpg-id";
          Service.Environment = keychainEnvironment;
        };
        xdg.configFile."proton-mail-mcp/config.toml".source =
          tomlFormat.generate "proton-mail-mcp-config.toml"
            {
              bridge = {
                username = cfg.address;
                password-file = "${mcpState}/bridge-password";
                certificate-file = "${mcpState}/cert.pem";
                draft-from = cfg.address;
              };
            };
        programs.mcp.servers.proton-mail.command = lib.getExe pkgs.proton-mail-mcp;
      };
    };
}
