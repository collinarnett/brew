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

    clan.core.vars.generators.kavita_oidc_client_secret = mkIf cfg.kanidm.enable {
      files.kavita_oidc_client_secret = { };
      runtimeInputs = [ pkgs.coreutils ];
      script = ''
        head -c 48 /dev/urandom | base64 --wrap=0 | tr -d '+/=' > "$out"/kavita_oidc_client_secret
      '';
    };

    services.kavita = {
      enable = true;
      tokenKeyFile = config.clan.core.vars.generators.kavita_token_key.files.kavita_token_key.path;
      settings = {
        IpAddresses = "127.0.0.1";
        # 5000 is taken by the docker registry.
        Port = 5001;
        OpenIdConnectSettings = mkIf cfg.kanidm.enable {
          Authority = "https://idm.trexd.dev/oauth2/openid/kavita";
          ClientId = "kavita";
          Secret = "@OIDC_SECRET@";
          ProvisionAccounts = true;
          SyncUserSettings = true;
          # Kavita refuses OIDC sign-in until the mandatory first-run admin
          # registration has been completed, so the OIDC identity links to
          # that initial account by shared email instead of a second account.
          AccountLinkingByEmail = true;
          # The kanidm claim map emits "kavita-Admin" in the groups claim,
          # which becomes the Kavita "Admin" role after prefix stripping.
          RolesClaim = "groups";
          RolesPrefix = "kavita-";
          AutoLogin = true;
          DisableLocalLogin = true;
        };
      };
    };

    systemd.services.kavita = mkIf cfg.kanidm.enable {
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
