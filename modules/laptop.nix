{ ... }:
{
  flake.modules.nixos.laptop =
    { config, lib, ... }:
    let
      cfg = config.brew.laptop;
    in
    {
      options.brew.laptop.enable = lib.mkEnableOption "laptop profile";
      config = lib.mkIf cfg.enable {
        # NixOS-level enables
        brew = {
          steam.enable = true;
          swayidle.enable = true;
        };
        # Forward to HM
        home-manager.sharedModules = [ { brew.laptop.enable = true; } ];
      };
    };

  flake.modules.homeManager.laptop =
    { config, lib, ... }:
    let
      cfg = config.brew.laptop;
    in
    {
      options.brew.laptop.enable = lib.mkEnableOption "laptop profile";
      config = lib.mkIf cfg.enable {
        brew = {
          swaylock.enable = true;
        };
      };
    };
}
