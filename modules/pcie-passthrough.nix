{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkOption mkIf;
  cfg = config.services.pcie-passthrough;
in {
  options.services.pcie-passthrough = let
    inherit (lib.types) str listOf;
  in {
    enable = mkEnableOption "pcie-passthrough";
    user = mkOption {
      type = str;
    };
    vfio-ids = mkOption {
      type = listOf str;
    };
    platform = mkOption {
      type = str;
    };
  };
  config = mkIf cfg.enable {
    boot = {
      kernelModules = ["kvm-${cfg.platform}" "vfio_virqfd" "vfio_pci" "vfio_iommu_type1" "vfio"];
      kernelParams = ["${cfg.platform}_iommu=on" "${cfg.platform}_iommu=pt" "kvm.ignore_msrs=1"];
      extraModprobeConfig = "options vfio-pci ids=${builtins.concatStringsSep "," cfg.vfio-ids}";
    };
    virtualisation.libvirtd = {
      enable = true;
      extraConfig = ''
        user='${cfg.user}'
      '';
      qemu.ovmf.enable = true;
      onBoot = "ignore";
      onShutdown = "shutdown";
    };
  };
}
