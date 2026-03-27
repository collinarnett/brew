{ ... }:
{
  flake.modules.nixos.xwayland-satellite =
    { config, lib, ... }:
    let
      cfg = config.brew.xwayland-satellite;
    in
    {
      options.brew.xwayland-satellite.enable = lib.mkEnableOption "xwayland-satellite";
      config = lib.mkIf cfg.enable {
        programs.sway.xwayland.enable = false;
        home-manager.sharedModules = [ { brew.xwayland-satellite.enable = true; } ];
      };
    };

  flake.modules.homeManager.xwayland-satellite =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.xwayland-satellite;
    in
    {
      options.brew.xwayland-satellite.enable = lib.mkEnableOption "xwayland-satellite";
      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.xrandr ];
        systemd.user.services.xwayland-satellite = {
          Install.WantedBy = [ "graphical-session.target" ];
          Unit = {
            Description = "Xwayland outside your Wayland";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            Type = "notify";
            NotifyAccess = "all";
            ExecStart = "${lib.getExe pkgs.xwayland-satellite} :1";
            ExecStartPost = "${pkgs.systemd}/bin/systemctl --user set-environment DISPLAY=:1";
            Restart = "on-failure";
          };
        };
      };
    };
}
