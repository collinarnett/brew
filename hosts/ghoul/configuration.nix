{ pkgs, ... }:
{
  imports = [
    ../../modules/cac.nix
    ../../modules/distributed-builds.nix
    ../../modules/firefox.nix
    ../../modules/greetd.nix
    ../../modules/pipewire.nix
    ../../modules/steam.nix
    ./disko.nix
    ./impermanence.nix
    ./modules/sops.nix
  ];

  services.cac.enable = true;
  services.emacs = {
    enable = true;
    startWithGraphical = true;
  };

  facter.reportPath = ./facter.json;

  boot.loader.systemd-boot.configurationLimit = 30;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

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

  networking.hostId = "b68778ef";

  boot = {
    # Newest kernels might not be supported by ZFS
    kernelParams = [
      "nohibernate"
    ];
    initrd.systemd = {
      enable = true;
      services.rollback = {
        description = "Rollback ZFS datasets to a pristine state";
        serviceConfig.Type = "oneshot";
        unitConfig.DefaultDependencies = "no";
        wantedBy = [ "initrd.target" ];
        after = [ "zfs-import-zroot.service" ];
        requires = [ "zfs-import-zroot.service" ];
        before = [ "sysroot.mount" ];
        path = with pkgs; [ zfs ];
        script = ''
          zfs rollback -r zroot/root@empty && echo "rollback complete"
        '';
      };
      services.create-needed-for-boot-dirs = {
        after = pkgs.lib.mkForce [ "rollback.service" ];
        wants = pkgs.lib.mkForce [ "rollback.service" ];
      };
    };
    initrd.supportedFilesystems.zfs = true;
    supportedFilesystems = [
      "vfat"
      "zfs"
    ];
    zfs = {
      forceImportAll = true;
    };
  };

  hardware.graphics.enable = true;
  services.tlp = {
    enable = true;
    settings = {
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 80;

      CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
      CPU_SCALING_GOVERNOR_ON_BAT = "schedutil";

      CPU_SCALING_MIN_FREQ_ON_AC = 800000;
      CPU_SCALING_MAX_FREQ_ON_AC = 3500000;
      CPU_SCALING_MIN_FREQ_ON_BAT = 800000;
      CPU_SCALING_MAX_FREQ_ON_BAT = 2300000;

      # Enable audio power saving for Intel HDA, AC97 devices (timeout in secs).
      # A value of 0 disables, >=1 enables power saving (recommended: 1).
      # Default: 0 (AC), 1 (BAT)
      SOUND_POWER_SAVE_ON_AC = 0;
      SOUND_POWER_SAVE_ON_BAT = 1;

      # Runtime Power Management for PCI(e) bus devices: on=disable, auto=enable.
      # Default: on (AC), auto (BAT)
      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";

      # Battery feature drivers: 0=disable, 1=enable
      # Default: 1 (all)
      NATACPI_ENABLE = 1;
      TPACPI_ENABLE = 1;
      TPSMAPI_ENABLE = 1;
    };
  }; # Flakes

  networking.hostName = "ghoul";
  networking.networkmanager.enable = true;

  time.timeZone = "America/New_York";

  programs.sway.enable = true;
  users.users.collin = {
    isNormalUser = true;
    shell = pkgs.zsh;
    hashedPassword = "$y$j9T$x.RDCNGwrERU4QtCPXuGB1$5hKCIlIQvWLFTiMI90EOCARUWWqUFDS2oXdYI8JrLe3";
    openssh.authorizedKeys.keyFiles = [
      ../../secrets/keys/collinarnett.pub
    ];
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
    ];
  };
  programs.zsh.enable = true;
  programs.dconf.enable = true; # fixes issue with home-manager

  services.blueman.enable = true;
  environment.systemPackages = with pkgs; [
    adwaita-icon-theme
    hunspellDicts.en_US
    wget
    git
    brightnessctl
  ];
  environment.sessionVariables = {
    GPG_TTY = "$(tty)";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  services.openssh.enable = true;
  security.pam.services.swaylock = { };

  system.stateVersion = "24.11";
}
