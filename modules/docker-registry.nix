{
  services.dockerRegistry.enable = true;
  services.dockerRegistry.garbageCollectDates = "monthly";
  services.dockerRegistry.enableGarbageCollect = true;
  services.dockerRegistry.listenAddress = "0.0.0.0";
}
