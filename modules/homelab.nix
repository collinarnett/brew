{
  config,
  lib,
  ...
}: let
  inherit (lib) mkIf mkEnableOption mkOption types;
  cfg = config.services.homelab;
in {
  imports = [
    ./authelia.nix
    ./jellyfin.nix
    ./searx.nix
    ./traefik.nix
  ];

  options.services.homelab = {
    enable = mkEnableOption "homelab";
    authelia = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "authelia";
        };
      };
    };
    jellyfin = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "jellyfin";
        };
      };
    };
    searx = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "searx";
        };
      };
    };
    traefik = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "traefik";
        };
      };
    };
  };

  config = {
    # TODO: Remove when moving to azathoth with impermanence since
    # creating groups and permmissions is built in to impermanence.
    users.groups.multimedia = {};
    systemd.tmpfiles.rules = [
      "d /media 0770 - multimedia - -"
    ];

    sops.secrets.searx_secret_key = mkIf cfg.traefik.enable {
      owner = config.systemd.services.traefik.serviceConfig.User;
    };
    sops.secrets.authelia_jwks_settings_file = mkIf cfg.authelia.enable {
      owner = config.systemd.services.authelia-main.serviceConfig.User;
    };
    sops.secrets.authelia_jwt_secret_file = mkIf cfg.authelia.enable {
      owner = config.systemd.services.authelia-main.serviceConfig.User;
    };
    sops.secrets.authelia_session_secret_file = mkIf cfg.authelia.enable {
      owner = config.systemd.services.authelia-main.serviceConfig.User;
    };
    sops.secrets.authelia_storage_encryption_key_file = mkIf cfg.authelia.enable {
      owner = config.systemd.services.authelia-main.serviceConfig.User;
    };
    sops.secrets.authelia_session_redis_password_file = mkIf cfg.authelia.enable {};
  };
}
