{
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        modules-left = ["cpu" "memory" "clock" "battery" "sway/workspaces"];
        modules = {
          "sway/workspaces" = {
            format = "{icon}";
            format-icons = {default = "";};
          };
          "clock" = {format = " {:%I:%M}";};
          "cpu" = {format = " {usage}%";};
          "memory" = {format = " {used:0.1f}G";};
          "battery" = {
            format = "{icon}{capacity}%";
            states = {
              warning = 30;
              critical = 15;
            };
            format-icons = ["" "" "" ""];
          };
        };
      };
    };
    style = ./style.css;
  };
}
