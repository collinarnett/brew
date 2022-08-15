{
  nixpkgs.config.allowUnfree = true;
  services.minecraft-server = {
    enable = true;
    eula = true;
    openFirewall = true;
    serverProperties = {
      difficulty = 3;
      server-port = 43000;
      motd = "Trexd's Minecraft Server";
    };
  };
}
