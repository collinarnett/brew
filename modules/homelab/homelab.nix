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
    sops.secrets.authelia_session_redis_password_file = mkIf cfg.authelia.enable { };
  };
}
