{
  pkgs,
  config,
  ...
}: {
  imports = [
    ../../modules/pipewire.nix
    ../../modules/sops.nix
    ../../modules/pcie-passthrough.nix
    ./impermanence.nix
    ./disko.nix
  ];

  # Hardware
  facter.reportPath = ./facter.json;

  # PCIE-Passthrough
  services.pcie-passthrough = {
    enable = true;
    user = "collin";
    platform = "amd";
    # GPU
    vfio-ids = ["10de:2204" "10de:1aef"];
  };

  # Filesystem
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/persist/save".neededForBoot = true;
  boot = {
    # Newest kernels might not be supported by ZFS
    kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
    kernelParams = [
      "nohibernate"
    ];
    initrd.systemd = {
      enable = true;
      services.rollback = {
        description = "Rollback ZFS datasets to a pristine state";
        serviceConfig.Type = "oneshot";
        unitConfig.DefaultDependencies = "no";
        wantedBy = ["initrd.target"];
        after = ["zfs-import-zroot.service"];
        wants = ["zfs-import-zroot.service"];
        before = ["sysroot.mount"];
        path = with pkgs; [zfs];
        script = ''
          zfs rollback -r zroot/root@empty && echo "rollback complete"
        '';
      };
      services.create-needed-for-boot-dirs.requires = ["rollback.service"];
    };
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
    hashedPassword = "$y$j9T$x.RDCNGwrERU4QtCPXuGB1$5hKCIlIQvWLFTiMI90EOCARUWWqUFDS2oXdYI8JrLe3";
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
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
    settings.PasswordAuthentication = true;
  };

  system.stateVersion = "24.11"; # Did you read the comment?
}
