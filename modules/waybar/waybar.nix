{ config, lib, ... }:
let
  cfg = config.brew.waybar;
  user = config.brew.user;
in
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
          modules-right = [ "clock" ];
          "sway/workspaces" = {
            format = "{icon}";
            format-icons = {
              default = "";
            };
          };
          "pulseaudio" = {
            format = " {volume}%";
          };
          "clock" = {
            format = " {:%A, %h %d %I:%M %p}";
          };
          "cpu" = {
            format = " {usage}%";
          };
          "disk" = {
            format = " {percentage_used}%";
          };
          "memory" = {
            format = " {used:0.1f}G";
          };
          "network" = {
            format = "{ifname}: {bandwidthDownBits} | {bandwidthUpBits}";
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
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.waybar = {
        enable = true;
        settings = cfg.settings;
        style = cfg.style;
      };
    };
  };
}
