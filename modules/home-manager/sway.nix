{ pkgs, ... }:
{
  home.packages = with pkgs; [
    emacs-all-the-icons-fonts
    fira-code
    fira-code-symbols
    siji
    noto-fonts-color-emoji
    ipafont
    liberation_ttf
  ];
  fonts.fontconfig.enable = true;

  wayland.windowManager.sway = {
    enable = true;
    checkConfig = false;
    wrapperFeatures.gtk = true;
    wrapperFeatures.base = true;
    config = {
      terminal = "kitty";
      output = {
        DP-4 = {
          bg = "/home/collin/Downloads/signal-2025-12-01-192702_002.jpg fill";
          subpixel = "none";
          scale = "2";
        };
      };
      modifier = "Mod4";
      bars = [ { command = "${pkgs.waybar}/bin/waybar"; } ];
      colors = {
        focused = {
          background = "#6272A4";
          border = "#6272A4";
          childBorder = "#6272A4";
          indicator = "#6272A4";
          text = "#F8F8F2";
        };
        focusedInactive = {
          background = "#44475A";
          border = "#44475A";
          childBorder = "#44475A";
          indicator = "#44475A";
          text = "#F8F8F2";
        };
        unfocused = {
          background = "#282A36";
          border = "#282A36";
          childBorder = "#282A36";
          indicator = "#282A36";
          text = "#BFBFBF";
        };
        urgent = {
          background = "#FF5555";
          border = "#44475A";
          childBorder = "#FF5555";
          indicator = "#FF5555";
          text = "#F8F8F2";
        };
        placeholder = {
          background = "#282A36";
          border = "#282A36";
          childBorder = "#282A36";
          indicator = "#282A36";
          text = "#F8F8F2";
        };
        background = "#F8F8F2";
      };
      window.titlebar = false;
      menu = "${pkgs.wofi}/bin/wofi";
    };
    extraConfig = ''
      set $mod Mod4
      bindsym XF86AudioRaiseVolume exec pactl set-sink-volume @DEFAULT_SINK@ +5%
      bindsym XF86AudioLowerVolume exec pactl set-sink-volume @DEFAULT_SINK@ -5%
      bindsym XF86AudioMute exec pactl set-sink-mute @DEFAULT_SINK@ toggle
      bindsym XF86AudioPlay exec playerctl play-pause
      bindsym XF86AudioNext exec playerctl next
      bindsym XF86AudioPrev exec playerctl previous
      bindsym $mod+p exec ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp -d)" - | ${pkgs.wl-clipboard}/bin/wl-copy -t image/png
    '';
  };
}
