{ config, ... }:

{
  services.ddclient = {
    enable = true;
    configFile = config.sops.secrets.ddclient-config.path;
  };
}
