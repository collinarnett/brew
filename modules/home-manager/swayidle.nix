{
  services.swayidle = {
    enable = true;
    events = [
      {
        event = "before-sleep";
        command = "swaylock";
      }
      {
        event = "lock";
        command = "lock";
      }
    ];
    timeouts = [
      {
        timeout = 120;
        command = "brightnessctl set 30%";
        resumeCommand = "brightnessctl set 80%";
      }
      {
        timeout = 300;
        command = ''
          swaylock -fF \
            -i /home/collin/pictures/purple_swamp_blured.jpg \
            -s fill \
            --font FiraCode \
            --indicator-radius 180 \
            --line-color 094129172 \                
            --text-color 236239244 \
            --inside-ver-color 129161193 \
            --line-ver-color 129161193 \
            --ring-ver-color 129161193 \
            --ring-color 116144173 \
            --key-hl-color 103128154 \
            --separator-color 103128154 \
            --layout-text-color 236239244 \
            --line-wrong-color 19197106 \
            --indicator-idle-visible
        '';
      }
      {
        timeout = 600;
        command = ''swaymsg "output * dpms off"'';
        resumeCommand = ''swaymsg "output * dpms on"'';
      }
      {
        timeout = 1200;
        command = "systemctl suspend";
        resumeCommand = ''swaymsg "output * dpms on"'';
      }
    ];
  };
}

