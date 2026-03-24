{ ... }:
{
  flake.modules.nixos.homelab =
    {
      config,
      lib,
      ...
    }:
    let
      inherit (lib)
        mkIf
        mkEnableOption
        mkOption
        types
        ;
      cfg = config.brew.homelab;
    in
    {
      imports = [
        ./_authelia.nix
        ./_jellyfin.nix
        ./_searx.nix
        ./_traefik.nix
        ./_calibre-web.nix
      ];

      options.brew.homelab = {
        enable = mkEnableOption "homelab";
        authelia = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "authelia";
            };
          };
        };
        calibre-web = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "calibre-web";
            };
          };
        };
        jellyfin = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "jellyfin";
            };
          };
        };
        searx = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "searx";
            };
          };
        };
        traefik = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "traefik";
            };
          };
        };
      };

      config = mkIf cfg.enable {
        users.groups.multimedia = { };
        systemd.tmpfiles.rules = [
          "d /media 0770 - multimedia - -"
        ];

        clan.core.vars.generators.searx_secret_key = mkIf cfg.traefik.enable {
          files.searx_secret_key = {
            owner = config.systemd.services.traefik.serviceConfig.User;
          };
          prompts.searx_secret_key = {
            description = "SearX secret key";
            type = "hidden";
            persist = true;
          };
        };

        clan.core.vars.generators.authelia_jwks_settings_file = mkIf cfg.authelia.enable {
          files.authelia_jwks_settings_file = {
            owner = config.systemd.services.authelia-main.serviceConfig.User;
          };
          prompts.authelia_jwks_settings_file = {
            description = "Authelia JWKS settings file contents";
            type = "multiline";
            persist = true;
          };
        };

        clan.core.vars.generators.authelia_jwt_secret_file = mkIf cfg.authelia.enable {
          files.authelia_jwt_secret_file = {
            owner = config.systemd.services.authelia-main.serviceConfig.User;
          };
          prompts.authelia_jwt_secret_file = {
            description = "Authelia JWT secret";
            type = "hidden";
            persist = true;
          };
        };

        clan.core.vars.generators.authelia_session_secret_file = mkIf cfg.authelia.enable {
          files.authelia_session_secret_file = {
            owner = config.systemd.services.authelia-main.serviceConfig.User;
          };
          prompts.authelia_session_secret_file = {
            description = "Authelia session secret";
            type = "hidden";
            persist = true;
          };
        };

        clan.core.vars.generators.authelia_storage_encryption_key_file = mkIf cfg.authelia.enable {
          files.authelia_storage_encryption_key_file = {
            owner = config.systemd.services.authelia-main.serviceConfig.User;
          };
          prompts.authelia_storage_encryption_key_file = {
            description = "Authelia storage encryption key";
            type = "hidden";
            persist = true;
          };
        };

        clan.core.vars.generators.authelia_session_redis_password_file = mkIf cfg.authelia.enable {
          files.authelia_session_redis_password_file = { };
          prompts.authelia_session_redis_password_file = {
            description = "Authelia session Redis password";
            type = "hidden";
            persist = true;
          };
        };
      };
    };
}
