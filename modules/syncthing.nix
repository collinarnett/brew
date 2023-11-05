{...}: {
  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    user = "collin";
    group = "users";
    dataDir = "/home/collin/.config/syncthing";
    configDir = "/home/collin/.config/syncthing";
    overrideFolders = true;
    overrideDevices = true;
    settings.folders = {
      music = {
        type = "sendonly";
        path = "/home/collin/music";
        label = "Music";
        devices = ["phone"];
      };
    };
    settings.devices = {
      phone = {
        id = "JDTY4DO-E7XF5ED-SECOGTO-F3HFJDA-R5LKSCN-B6DKULO-GCJ5JKH-HYUT3QF";
      };
    };
  };
}
