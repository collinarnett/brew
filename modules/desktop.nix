{ ... }:
{
  flake.modules.nixos.desktop =
    { config, lib, ... }:
    let
      cfg = config.brew.desktop;
    in
    {
      options.brew.desktop.enable = lib.mkEnableOption "desktop profile";
      config = lib.mkIf cfg.enable {
        # NixOS-level enables (pure NixOS + NixOS side of mixed modules)
        brew = {
          cac.enable = true;
          firefox.enable = true;
          greetd.enable = true;
          pipewire.enable = true;
          sway.enable = true;
          waybar.enable = true;
          xdg-portal.enable = true;
          obs-studio.enable = true;
        };
        # Forward to HM
        home-manager.sharedModules = [ { brew.desktop.enable = true; } ];
      };
    };

  flake.modules.homeManager.desktop =
    { config, lib, ... }:
    let
      cfg = config.brew.desktop;
    in
    {
      options.brew.desktop.enable = lib.mkEnableOption "desktop profile";
      config = lib.mkIf cfg.enable {
        brew = {
          gtk.enable = true;
          kitty.enable = true;
          mako.enable = true;
          wofi.enable = true;
          xdg-mime.enable = true;
          zathura.enable = true;
        };
      };
    };
}
