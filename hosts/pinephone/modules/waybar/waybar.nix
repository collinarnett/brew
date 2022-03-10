{
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        modules-left = [ "cpu" "disk" "memory" "network" ];
        modules-center = [ "sway/workspaces" ];
        modules-right = [ "clock" ];
        modules = {
          "sway/workspaces" = {
            format = "{icon}";
            format-icons = { default = ""; };
          };
          "clock" = { format = " {:%A, %h %d %I:%M %p}"; };
          "cpu" = { format = " {usage}%"; };
          "disk" = { format = " {percentage_used}%"; };
          "memory" = { format = " {used:0.1f}G"; };
          "network" = {
            format = "{ifname}: {bandwidthDownBits} | {bandwidthUpBits}";
          };
        };
      };
    };
    style = ./style.css;
  };
}
