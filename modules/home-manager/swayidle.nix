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
        command = "swaylock";
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

