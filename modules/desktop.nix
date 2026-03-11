{ ... }:
{
  flake.nixosModules.desktop =
    { config, lib, ... }:
    let
      cfg = config.brew.desktop;
    in
    {
      options.brew.desktop.enable = lib.mkEnableOption "desktop profile";
      config = lib.mkIf cfg.enable {
        brew = {
          cac.enable = true;
          firefox.enable = true;
          greetd.enable = true;
          gtk.enable = true;
          kitty.enable = true;
          mako.enable = true;
          pipewire.enable = true;
          sway.enable = true;
          waybar.enable = true;
          wofi.enable = true;
          xdg-mime.enable = true;
          xdg-portal.enable = true;
          obs-studio.enable = true;
          zathura.enable = true;
        };
      };
    };
}
