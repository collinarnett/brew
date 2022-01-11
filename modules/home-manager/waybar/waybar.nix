{
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        modules-left = [ "cpu" "pulseaudio" "disk" "memory" "mpd" ];
        modules-center = [ "sway/workspaces" ];
        modules-right = [ "clock" ];
        modules = {
          "sway/workspaces" = {
            format = "{icon}";
            format-icons = { default = ""; };
          };
          "pulseaudio" = { format = " {volume}%"; };
          "mpd" = { format = " {title}"; };
          "clock" = { format = " {:%A, %h %d %I:%M %p}"; };
          "cpu" = { format = " {usage}%"; };
          "disk" = { format = " {percentage_used}%"; };
          "memory" = { format = " {used:0.1f}G"; };
        };
      };
    };
    style = ./style.css;
  };
}
