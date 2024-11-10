{
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        modules-left = ["cpu" "pulseaudio" "disk" "memory" "mpd" "network"];
        modules-center = ["sway/workspaces"];
        modules-right = ["clock"];
        "sway/workspaces" = {
          format = "{icon}";
          format-icons = {default = "";};
        };
        "pulseaudio" = {format = " {volume}%";};
        "mpd" = {format = " {title}";};
        "clock" = {format = " {:%A, %h %d %I:%M %p}";};
        "cpu" = {format = " {usage}%";};
        "disk" = {format = " {percentage_used}%";};
        "memory" = {format = " {used:0.1f}G";};
        "network" = {format = "{ifname}: {bandwidthDownBits} | {bandwidthUpBits}";};
      };
    };
    style = ./style.css;
  };
}
