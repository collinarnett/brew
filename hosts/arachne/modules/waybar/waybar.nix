{
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        modules-left = [ "cpu" "memory" "pulseaudio" "disk" "battery" ];
        modules-center = [ "sway/workspaces" ];
        modules-right = [ "clock" ];
        modules = {
          "sway/workspaces" = {
            format = "{icon}";
            format-icons = { default = ""; };
          };
          "clock" = { format = " {:%I:%M}"; };
          "cpu" = { format = " {usage}%"; };
          "pulseaudio" = { format = " {volume}%"; };
          "disk" = { format = " {percentage_used}%"; };
          "mpd" = { format = " {title}"; };
          "memory" = { format = " {used:0.1f}G"; };
          "battery" = {
            format = "{icon}{capacity}%";
            states = {
              warning = 30;
              critical = 15;
            };
            format-icons = [ "" "" "" "" ];
          };
        };
      };
    };
    style = ./style.css;
  };
}
