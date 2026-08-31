{ ... }:
{
  flake.modules.nixos.xdg-portal =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.xdg-portal;
    in
    {
      options.brew.xdg-portal.enable = lib.mkEnableOption "xdg-portal";
      config = lib.mkIf cfg.enable {
        xdg.portal = {
          enable = true;
          xdgOpenUsePortal = false;
          config.sway = {
            default = lib.mkForce [
              "wlr"
              "gtk"
            ];
            "org.freedesktop.impl.portal.Notification" = "none";
          };
          extraPortals = with pkgs; [
            xdg-desktop-portal-wlr
            xdg-desktop-portal-gtk
          ];
          # Click an output to cast it. A simple chooser must print a name
          # prefixed with "Monitor: "; anything else counts as the user
          # declining the cast.
          wlr.settings.screencast = {
            chooser_type = "simple";
            chooser_cmd = "${pkgs.slurp}/bin/slurp -f 'Monitor: %o' -or";
          };
        };
      };
    };
}
