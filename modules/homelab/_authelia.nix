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
  config = mkIf (cfg.enable && cfg.authelia.enable) {
    services.authelia.instances = {
      main = {
        enable = true;
        settingsFiles = [ config.sops.secrets.authelia_jwks_settings_file.path ];
        secrets.jwtSecretFile = config.sops.secrets.authelia_jwt_secret_file.path;
        secrets.sessionSecretFile = config.sops.secrets.authelia_session_secret_file.path;
        secrets.storageEncryptionKeyFile = config.sops.secrets.authelia_storage_encryption_key_file.path;
        settings.default_2fa_method = "totp";
        settings = {
          authentication_backend.file.path = "/var/lib/authelia-main/users_database.yml";
          storage.local.path = "/var/lib/authelia-main/db.sqlite3";
          regulation = {
            ban_time = 300;
            find_time = 120;
            max_retries = 3;
          };
          session = {
            domain = "trexd.dev";
            expiration = 604800;
            inactivity = 300;
            name = "authelia_session";
          };
          notifier = {
            disable_startup_check = false;
            filesystem = {
              filename = "/var/lib/authelia-main/notification.txt";
            };
          };
          identity_providers.oidc = {
            clients = mkIf cfg.jellyfin.enable [
              {
                id = "jellyfin";
                description = "Jellyfin";
                secret = "$pbkdf2-sha512$310000$YTPOIu.8sypt1DNtvPDj2Q$JPUVH7/9lnMOPrfQnzveXnA3e46uSBG3bw4j8I84COOJNCf1CKr8wJ/VKw/kgk1V2lULxUixiK9y4iFDPSIiPA";
                authorization_policy = "two_factor";
                redirect_uris = [
                  "https://media.trexd.dev/sso/OID/start/authelia"
                ];
                scopes = [
                  "openid"
                  "profile"
                  "groups"
                ];
              }
            ];
          };
          access_control = {
            default_policy = "deny";
            rules = [
              {
                domain = "*.trexd.dev";
                policy = "two_factor";
              }
            ];
          };
        };
      };
    };
  };
}
