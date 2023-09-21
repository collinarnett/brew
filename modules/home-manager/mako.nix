{...}: {
  services.mako = {
    enable = true;
    backgroundColor = "#282a36";
    textColor = "#f8f8f2";
    borderColor = "#282a36";
    defaultTimeout = 5000;
    extraConfig = ''
      [urgency=low]
      border-color=#8be9fd

      [urgency=normal]
      border-color=#6272a4

      [urgency=high]
      border-color=#ff5555
    '';
  };
}
