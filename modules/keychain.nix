{ ... }:
let
  keychainOptions =
    { lib, ... }:
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
        enableZshIntegration = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to enable zsh integration";
        };
      };
    };
in
{
  flake.modules.nixos.keychain =
    { config, lib, ... }:
    let
      cfg = config.brew.keychain;
    in
    {
      imports = [ keychainOptions ];
      config = lib.mkIf cfg.enable {
        home-manager.sharedModules = [
          {
            brew.keychain = {
              enable = true;
              inherit (cfg) keys extraFlags enableZshIntegration;
            };
          }
        ];
      };
    };

  flake.modules.homeManager.keychain =
    { config, lib, ... }:
    let
      cfg = config.brew.keychain;
    in
    {
      imports = [ keychainOptions ];
      config = lib.mkIf cfg.enable {
        programs.keychain = {
          enable = true;
          enableZshIntegration = cfg.enableZshIntegration;
          extraFlags = cfg.extraFlags;
          keys = cfg.keys;
        };
      };
    };
}
