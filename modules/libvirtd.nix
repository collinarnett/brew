{ pkgs, config, ... }:
{

  boot.initrd.availableKernelModules = [ "amdgpu" "vfio-pci" ];
  boot.initrd.preDeviceCommands = ''
    DEVS="0000:0f:00.0 0000:0f:00.1"
    for DEV in $DEVS; do
      echo "vfio-pci" > /sys/bus/pci/devices/$DEV/driver_override
    done
    modprobe -i vfio-pci
  '';

  systemd.services.libvirtd.path = [ pkgs.parted ];

  boot.kernelParams = [ "amd_iommu=on" "pcie_aspm=off" ];

  virtualisation.libvirtd = {
    enable = true;
    extraConfig = ''
      user='collin'
    '';
    qemu = {
      ovmf.enable = true;
      verbatimConfig = ''
        cgroup_device_acl = [
          "/dev/null",
          "/dev/full",
          "/dev/zero",
          "/dev/random",
          "/dev/urandom",
          "/dev/ptmx",
          "/dev/kvm",
          "/dev/kqemu",
          "/dev/rtc",
          "/dev/hpet",
          "/dev/by-input/usb-ZSA_Technology_Labs_Planck_EZ_Glow-if01-event-kbd"
        ]
      '';
    };
    onBoot = "ignore";
    onShutdown = "shutdown";
  };
  users.users.qemu-libvirtd.extraGroups = [ "input" ];
}
