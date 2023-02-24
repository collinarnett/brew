{
  pkgs,
  config,
  ...
}: {
  wayland.windowManager.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    config = {
      terminal = "footclient";
      bars = [{command = "${pkgs.waybar}/bin/waybar";}];
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
      input."0:0:PinePhone_Keyboard" = {
        xkb_file = builtins.toString ./pinephone-keyboard.xkb;
        repeat_delay = "500";
        repeat_rate = "15";
      };
    };
    extraConfig = ''
      set $mod Mod4
      bindsym $mod+p exec grim -g "$(slurp -d)" - | wl-copy -t image/png
      bindsym $mod+t exec swaymsg output DSI-1 transform 90
    '';
  };
}
