{
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
    ../../modules/apcupsd.nix
    ../../modules/cac.nix
    ../../modules/greetd.nix
    ../../modules/homelab.nix
    ../../modules/pcie-passthrough.nix
    ../../modules/pipewire.nix
    ../../modules/restic.nix
    ../../modules/sops.nix
    ./disko.nix
    ./impermanence.nix
  ];
  # Browser
  programs.firefox.enable = true;

  services.cac.enable = true;

  services.homelab = {
    enable = true;
    searx.enable = true;
    traefik.enable = true;
    authelia.enable = true;
    jellyfin.enable = true;
    calibre-web.enable = true;
  };

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
  fileSystems = {
    "/persist" = {
      device = "zroot/persist";
      fsType = "zfs";
      neededForBoot = true;
    };
    "/persist/save" = {
      device = "zroot/persistSave";
      fsType = "zfs";
      neededForBoot = true;
    };
  };
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
        requires = ["zfs-import-zroot.service"];
        before = ["sysroot.mount"];
        path = with pkgs; [zfs];
        script = ''
          zfs rollback -r zroot/root@empty && echo "rollback complete"
        '';
      };
      services.create-needed-for-boot-dirs = {
        after = pkgs.lib.mkForce ["rollback.service"];
        wants = pkgs.lib.mkForce ["rollback.service"];
      };
    };
    initrd.supportedFilesystems.zfs = true;
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
      ../../secrets/keys/arachne.pub
    ];
  };

  # Temporary for setup
  users.users.root.openssh.authorizedKeys.keyFiles = [
    ../../secrets/keys/collinarnett.pub
  ];

  nix.settings.trusted-users = ["collin"];

  # Man pages
  documentation.dev.enable = true;

  # Graphics
  hardware.graphics.enable = true;

  # SSH
  services.openssh = {
    enable = true;
    ports = [8787];
    settings.PermitRootLogin = "yes";
    hostKeys = [
      {
        type = "ed25519";
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
      }
      {
        type = "rsa";
        bits = 4096;
        path = "/persist/etc/ssh/ssh_host_rsa_key";
      }
    ];
    settings.PasswordAuthentication = true;
  };

  system.stateVersion = "24.11"; # Did you read the comment?
}
