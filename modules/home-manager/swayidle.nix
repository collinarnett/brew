{
  programs.swayidle = {
    enable = true;
    events = [
      { event = "before-sleep"; command = "swaylock"; }
    ];
  };
}

