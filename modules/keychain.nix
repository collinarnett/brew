{ config, lib, ... }:
let
  cfg = config.brew.keychain;
  user = config.brew.user;
in
{
  options.brew.keychain = {
    enable = lib.mkEnableOption "keychain";
    keys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "id_ed25519" ];
      description = "SSH keys to manage with keychain";
    };
    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "--systemd" ];
      description = "Extra flags to pass to keychain";
    };
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.keychain = {
        enable = true;
        enableZshIntegration = true;
        extraFlags = cfg.extraFlags;
        keys = cfg.keys;
      };
    };
  };
}
