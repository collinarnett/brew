{ ... }:
{
  flake.modules.nixos.zoom =
    { config, lib, ... }:
    let
      cfg = config.brew.zoom;
    in
    {
      options.brew.zoom.enable = lib.mkEnableOption "zoom";
      config = lib.mkIf cfg.enable {
        programs.zoom-us.enable = true;
      };
    };
}
