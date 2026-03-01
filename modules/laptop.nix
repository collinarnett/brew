{ ... }:
{
  flake.nixosModules.laptop =
    { config, lib, ... }:
    let
      cfg = config.brew.laptop;
    in
    {
      options.brew.laptop.enable = lib.mkEnableOption "laptop profile";
      config = lib.mkIf cfg.enable {
        brew = {
          distributed-builds.enable = true;
          steam.enable = true;
          swayidle.enable = true;
          swaylock.enable = true;
        };
      };
    };
}
