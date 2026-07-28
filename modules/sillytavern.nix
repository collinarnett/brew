{ ... }:
{
  flake.modules.nixos.sillytavern =
    { config, lib, ... }:
    let
      cfg = config.brew.sillytavern;
    in
    {
      options.brew.sillytavern.enable = lib.mkEnableOption "sillytavern";
      config = lib.mkIf cfg.enable {
        services.sillytavern = {
          enable = true;
        };

        # SillyTavern rewrites config.yaml at startup; seed a writable copy
        # instead of the nixpkgs module's read-only store symlink (EROFS).
        systemd.tmpfiles.settings.sillytavern."/var/lib/SillyTavern/config.yaml" = lib.mkForce {
          C = {
            mode = "0600";
            user = config.services.sillytavern.user;
            group = config.services.sillytavern.group;
            argument = toString config.services.sillytavern.configFile;
          };
        };
      };
    };
}
