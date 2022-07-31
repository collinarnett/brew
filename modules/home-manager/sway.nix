{ pkgs, ... }:

{
  wayland.windowManager.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    config = {
      terminal = "kitty";
      #    input = {
      #      "*" = {
      #        repeat_delay = "180";
      #        repeat_rate = "31";
      #      };
      #    };
      output = {
        DP-3 = {
          bg = "#282a36 solid_color";
          subpixel = "none";
        };
        DP-1 = {
          bg = "#282a36 solid_color";
          subpixel = "none";
        };
      };
      bars = [{ command = "${pkgs.waybar}/bin/waybar"; }];
      colors = {
        focused = {
          background = "#21222c";
          border = "#ff79c6";
          childBorder = "ff79c6";
          indicator = "8be9fd";
          text = "f8f8f2";
        };
      };
      menu = "${pkgs.wofi}/bin/wofi";
    };
    extraConfig = ''
      set $mod Mod4
      bindsym XF86AudioRaiseVolume exec pactl set-sink-volume @DEFAULT_SINK@ +5%
      bindsym XF86AudioLowerVolume exec pactl set-sink-volume @DEFAULT_SINK@ -5%
      bindsym XF86AudioMute exec pactl set-sink-mute @DEFAULT_SINK@ toggle
      bindsym XF86AudioMicMute exec pactl set-source-mute @DEFAULT_SOURCE@ toggle
      bindsym XF86AudioPlay exec playerctl play-pause
      bindsym XF86AudioNext exec playerctl next
      bindsym XF86AudioPrev exec playerctl previous
      bindsym $mod+p exec grim -g "$(slurp -d)" - | wl-copy -t image/png
    '';
    extraSessionCommands = ''
      pactl set-default-sink alsa_output.pci-0000_11_00.4.iec958-stereo
    '';
    #exec systemctl --user import-environment XDG_SESSION_TYPE XDG_CURRENT_DESKTOP
    #exec dbus-update-activation-environment WAYLAND_DISPLAY
  };
}
