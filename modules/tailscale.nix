{ config, ... }:
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };
}
