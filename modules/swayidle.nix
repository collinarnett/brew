{ ... }:
let
  swayidleOptions =
    { lib, ... }:
    {
      options.brew.swayidle = {
        enable = lib.mkEnableOption "swayidle";
        enableDpms = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to enable dpms timeout (turn off displays after lock)";
        };
      };
    };
in
{
  flake.modules.nixos.swayidle =
    { config, lib, ... }:
    let
      cfg = config.brew.swayidle;
    in
    {
      imports = [ swayidleOptions ];
      config = lib.mkIf cfg.enable {
        home-manager.sharedModules = [
          {
            brew.swayidle = {
              enable = true;
              inherit (cfg) enableDpms;
            };
          }
        ];
      };
    };

  flake.modules.homeManager.swayidle =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.swayidle;
      dpmsTimeout = lib.optional cfg.enableDpms {
        timeout = 310;
        command = ''${pkgs.sway}/bin/swaymsg "output * dpms off"'';
        resumeCommand = ''${pkgs.sway}/bin/swaymsg "output * dpms on"'';
      };
    in
    {
      imports = [ swayidleOptions ];
      config = lib.mkIf cfg.enable {
        services.swayidle = {
          enable = true;
          events = [
            {
              event = "before-sleep";
              command = "${pkgs.swaylock}/bin/swaylock -f";
            }
            {
              event = "lock";
              command = "${pkgs.swaylock}/bin/swaylock -f";
            }
          ];
          timeouts =
            [
              {
                timeout = 300;
                command = "${pkgs.swaylock}/bin/swaylock -f";
              }
            ]
            ++ dpmsTimeout
            ++ [
              {
                timeout = 600;
                command = "${pkgs.systemd}/bin/systemctl suspend";
              }
            ];
        };
      };
    };
}
