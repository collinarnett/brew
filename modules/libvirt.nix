{ pkgs, ... }:

{

  boot.initrd.availableKernelModules = [ "amdgpu" "vfio-pci" ];
  boot.initrd.preDeviceCommands = ''
    DEVS="0000:0f:00.0 0000:0f:00.1"
    for DEV in $DEVS; do
      echo "vfio-pci" > /sys/bus/pci/devices/$DEV/driver_override
    done
    modprobe -i vfio-pci
  '';

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [ "amd_iommu=on" "pcie_aspm=off" ];

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      ovmf.enable = true;
      runAsRoot = false;
    };
    onBoot = "ignore";
    onShutdown = "shutdown";
  };
}
