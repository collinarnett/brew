{
  networking.firewall.enable = false;
  # networking.firewall.allowedTCPPorts = [8083];
  # networking.firewall.allowedUDPPorts = [8083];
  services.calibre-web = {
    enable = true;
    user = "collin";
    listen.ip = "0.0.0.0";
    options.enableBookUploading = true;
  };
}
