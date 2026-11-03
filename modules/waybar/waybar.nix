{ ... }:
let
  waybarOptions =
    { lib, ... }:
    {
      options.brew.waybar = {
        enable = lib.mkEnableOption "waybar";
        settings = lib.mkOption {
          type = lib.types.attrs;
          default = {
            mainBar = {
              modules-left = [
                "cpu"
                "pulseaudio"
                "disk"
                "memory"
                "network"
              ];
              modules-center = [ "sway/workspaces" ];
              modules-right = [
                "custom/tomat"
                "clock"
                "tray"
              ];
              "sway/workspaces" = {
                format = "{icon}";
                format-icons = {
                  default = "";
                };
              };
              "pulseaudio" = {
                format = " {volume}%";
              };
              "clock" = {
                format = " {:%A, %h %d %I:%M %p}";
              };
              "cpu" = {
                format = " {usage}%";
              };
              "disk" = {
                format = " {percentage_used}%";
              };
              "memory" = {
                format = " {used:0.1f}G";
              };
              "network" = {
                format = "{ifname}: {bandwidthDownBits} | {bandwidthUpBits}";
              };
              "custom/tomat" = {
                exec = "tomat status";
                interval = 1;
                return-type = "json";
                format = "{}";
                on-click = "tomat toggle";
                on-click-right = "tomat skip";
              };
            };
          };
          description = "Waybar settings";
        };
        style = lib.mkOption {
          type = lib.types.path;
          default = ./style.css;
          description = "Waybar style CSS file";
        };
      };
    };
in
{
  flake.modules.nixos.waybar =
    { config, lib, ... }:
    let
      cfg = config.brew.waybar;
    in
    {
      imports = [ waybarOptions ];
      config = lib.mkIf cfg.enable {
        home-manager.sharedModules = [
          {
            brew.waybar = {
              enable = true;
              inherit (cfg) settings style;
            };
          }
        ];
      };
    };

  flake.modules.homeManager.waybar =
    { config, lib, ... }:
    let
      cfg = config.brew.waybar;
      modulesRight = cfg.settings.mainBar.modules-right;
      # The audio-output switcher is host-specific (tied to azathoth's codec), so
      # its waybar button is contributed only when that leaf is enabled. Hosts
      # without it never reference the missing `audio-output` command.
      settings =
        if config.brew.audio-output.enable or false then
          cfg.settings
          // {
            mainBar = cfg.settings.mainBar // {
              # The tray sits immediately left of the switcher.
              modules-right =
                lib.optional (lib.elem "tray" modulesRight) "tray"
                ++ [ "custom/audio-output" ]
                ++ lib.remove "tray" modulesRight;
              "custom/audio-output" = {
                exec = "audio-output status";
                interval = 5;
                return-type = "json";
                format = "{}";
                on-click = "audio-output menu";
                signal = 8;
              };
            };
          }
        else
          cfg.settings;
    in
    {
      imports = [ waybarOptions ];
      config = lib.mkIf cfg.enable {
        programs.waybar = {
          enable = true;
          inherit settings;
          style = cfg.style;
        };
      };
    };
}
