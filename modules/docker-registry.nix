{ config, lib, ... }:
let
  cfg = config.brew.docker-registry;
in
{
  options.brew.docker-registry.enable = lib.mkEnableOption "docker-registry";
  config = lib.mkIf cfg.enable {
    services.dockerRegistry.enable = true;
    services.dockerRegistry.garbageCollectDates = "monthly";
    services.dockerRegistry.enableGarbageCollect = true;
    services.dockerRegistry.listenAddress = "0.0.0.0";
  };
}
