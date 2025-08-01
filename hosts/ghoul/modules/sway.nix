{
  pkgs,
  config,
  ...
}:
{
  wayland.windowManager.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    checkConfig = false;
    config = {
      terminal = "kitty";
      bars = [ { command = "${pkgs.waybar}/bin/waybar"; } ];
      output = {
        DP-3 = {
          position = "0 0";  # top display
          bg = "/home/collin/Pictures/purple_swamp.jpg fill";
        };
        eDP-1 = {
          transform = "normal";
          position = "0 1800";  # stacked below DP-3
          bg = "/home/collin/Pictures/purple_swamp.jpg fill";
        };
      };
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
      for_window [class=".*"] inhibit_idle fullscreen
      for_window [app_id=".*"] inhibit_idle fullscreen
      set $mod Mod4
      bindsym XF86MonBrightnessDown exec "brightnessctl set 2%-"
      bindsym XF86MonBrightnessUp exec "brightnessctl set +2%"
      bindsym XF86AudioRaiseVolume exec pactl set-sink-volume @DEFAULT_SINK@ +5%
      bindsym XF86AudioLowerVolume exec pactl set-sink-volume @DEFAULT_SINK@ -5%
      bindsym XF86AudioMute exec pactl set-sink-mute @DEFAULT_SINK@ toggle
      bindsym XF86AudioMicMute exec pactl set-source-mute @DEFAULT_SOURCE@ toggle
      bindsym XF86AudioPlay exec playerctl play-pause
      bindsym XF86AudioNext exec playerctl next
      bindsym XF86AudioPrev exec playerctl previous
      bindsym $mod+p exec ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp -d)" - | wl-copy -t image/png
      bindsym $mod+l exec ${pkgs.swaylock}/bin/swaylock
    '';
  };
}
