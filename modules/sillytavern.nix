{ ... }:
{
  flake.nixosModules.sillytavern =
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
      };
    };
}
