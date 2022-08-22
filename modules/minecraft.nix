{
  nixpkgs.config.allowUnfree = true;
  services.minecraft-server = {
    enable = true;
    eula = true;
    openFirewall = true;
    serverProperties = {
      difficulty = 3;
      server-port = 43000;
      white-list = true;
      motd = "Trexd's Minecraft Server";
    };
    whitelist = {
      username1 = "11d6395d-f023-497e-aead-e81bd890af53";
      username2 = "3b533499-2878-4108-b11f-c1193416621b";
    };
    declarative = true;
  };
}
