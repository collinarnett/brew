{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.brew.homelab;
in
{
  config = mkIf (cfg.enable && cfg.kavita.enable) {
    clan.core.vars.generators.kavita_token_key = {
      files.kavita_token_key.owner = "kavita";
      runtimeInputs = [ pkgs.coreutils ];
      # Kavita requires a JWT signing key of at least 512 bits.
      script = ''
        head -c 64 /dev/urandom | base64 --wrap=0 > "$out"/kavita_token_key
      '';
    };

    # The plaintext secret goes to Kavita; Authelia's client registry only
    # ever sees the pbkdf2 digest, which is safe to keep as a world-readable
    # var and reference at eval time.
    clan.core.vars.generators.kavita_oidc_client_secret = mkIf cfg.authelia.enable {
      files.kavita_oidc_client_secret = { };
      files.kavita_oidc_client_secret_digest.secret = false;
      runtimeInputs = with pkgs; [
        coreutils
        gnused
        authelia
      ];
      script = ''
        head -c 48 /dev/urandom | base64 --wrap=0 | tr -d '+/=' > "$out"/kavita_oidc_client_secret
        authelia crypto hash generate pbkdf2 --variant sha512 \
          --password "$(cat "$out"/kavita_oidc_client_secret)" \
          | sed 's/^Digest: //' | tr -d '\n' > "$out"/kavita_oidc_client_secret_digest
      '';
    };

    services.kavita = {
      enable = true;
      tokenKeyFile = config.clan.core.vars.generators.kavita_token_key.files.kavita_token_key.path;
      settings = {
        IpAddresses = "127.0.0.1";
        # 5000 is taken by the docker registry.
        Port = 5001;
        OpenIdConnectSettings = mkIf cfg.authelia.enable {
          Authority = "https://login.trexd.dev";
          ClientId = "kavita";
          Secret = "@OIDC_SECRET@";
          ProvisionAccounts = true;
          SyncUserSettings = true;
          CustomScopes = [ "groups" ];
          # Authelia group "kavita-Admin" becomes the Kavita "Admin" role.
          RolesClaim = "groups";
          RolesPrefix = "kavita-";
          AutoLogin = true;
          DisableLocalLogin = true;
        };
      };
    };

    systemd.services.kavita = mkIf cfg.authelia.enable {
      serviceConfig.LoadCredential = [
        "oidc-secret:${config.clan.core.vars.generators.kavita_oidc_client_secret.files.kavita_oidc_client_secret.path}"
      ];
      preStart = lib.mkAfter ''
        ${pkgs.replace-secret}/bin/replace-secret '@OIDC_SECRET@' \
          ''${CREDENTIALS_DIRECTORY}/oidc-secret \
          '/var/lib/kavita/config/appsettings.json'
      '';
    };

    users.users.kavita.extraGroups = [ "multimedia" ];
  };
}
