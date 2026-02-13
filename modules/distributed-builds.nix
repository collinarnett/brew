{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.brew.distributed-builds;
in
{
  options.brew.distributed-builds.enable = lib.mkEnableOption "distributed-builds";
  config = lib.mkIf cfg.enable {
    nix.distributedBuilds = true;
    nix.settings.builders-use-substitutes = true;

    nix.buildMachines = [
      {
        hostName = "azathoth";
        sshUser = "remotebuild";
        sshKey = "/root/.ssh/remotebuild";
        system = pkgs.stdenv.hostPlatform.system;
        supportedFeatures = [
          "nixos-test"
          "big-parallel"
          "kvm"
        ];
      }
    ];
  };
}
