{
  pkgs,
  config,
  ...
}: {
  imports = [
    ../../modules/pipewire.nix
    ../../modules/sops.nix
    ./impermanence.nix
    ./disko.nix
  ];

  # Hardware
  facter.reportPath = ./facter.json;

  # Filesystem
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/persist/save".neededForBoot = true;
  boot = {
    # Newest kernels might not be supported by ZFS
    kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
    kernelParams = [
      "nohibernate"
    ];
    initrd.postDeviceCommands =
      #wipe / and /var on boot
      ''
        zfs rollback -r zroot/root@empty
      '';
    supportedFilesystems = ["vfat" "zfs"];
    zfs = {
      forceImportAll = true;
    };
  };

  # Editor
  services.emacs = {
    enable = true;
    defaultEditor = true;
    startWithGraphical = true;
  };

  # General
  boot.loader.systemd-boot.configurationLimit = 30;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "America/New_York";
  programs.zsh.enable = true;

  # Networking
  networking = {
    hostName = "azathoth";
    # head -c 8 /etc/machine-id
    hostId = "20556d4b";
    nameservers = ["1.1.1.1" "9.9.9.9"];
  };

  # Users
  users.users.collin = {
    isNormalUser = true;
    extraGroups = [
      "video"
      "wheel"
      "libvirtd"
      "input"
      "audio"
      "docker"
      "adbusers"
      "multimedia"
      "aws"
    ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keyFiles = [
      ../../secrets/keys/collinarnett.pub
    ];
  };

  # Temporary for setup
  users.users.root.openssh.authorizedKeys.keyFiles = [
    ../../secrets/keys/collinarnett.pub
  ];

  nix.settings.trusted-users = ["collin"];

  # Man pages
  documentation.dev.enable = true;

  # SSH
  services.openssh = {
    enable = true;
    ports = [8787];
    settings.PermitRootLogin = "yes";
    settings.PasswordAuthentication = true;
  };

  system.stateVersion = "24.11"; # Did you read the comment?
}
