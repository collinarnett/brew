{ pkgs, ... }:

{
  wayland.windowManager.sway = {
    enable = true;
    config = {
      terminal = "kitty";
      output = {
        Virtual-1 = {
          bg = "~/pictures/1610399969845.jpg fill";
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
      bindsym XF86AudioRaiseVolume exec pactl set-sink-volume @DEFAULT_SINK@ +5%
      bindsym XF86AudioLowerVolume exec pactl set-sink-volume @DEFAULT_SINK@ -5%
      bindsym XF86AudioMute exec pactl set-sink-mute @DEFAULT_SINK@ toggle
      bindsym XF86AudioMicMute exec pactl set-source-mute @DEFAULT_SOURCE@ toggle
      bindsym XF86AudioPlay exec playerctl play-pause
      bindsym XF86AudioNext exec playerctl next
      bindsym XF86AudioPrev exec playerctl previous
    '';
  };
}
