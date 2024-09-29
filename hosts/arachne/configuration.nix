{pkgs, ...}: {
  imports = [
    ../../modules/pipewire.nix
    ../../modules/greetd.nix
    ./modules/sops.nix
  ];

  services.emacs = {
    enable = true;
    startWithGraphical = true;
    package = (import ../../modules/emacs/emacs.nix) pkgs;
  };

  zfs-root = {
    boot = {
      devNodes = "/dev/disk/by-id/";
      bootDevices = ["ata-CT480BX500SSD1_2246E686D9FD" "ata-CT480BX500SSD1_2303E69EE264"];
      immutable = false;
      availableKernelModules = ["xhci_pci" "ehci_pci" "ahci" "usb_storage" "sd_mod" "rtsx_pci_sdmmc"];
      removableEfi = true;
      kernelParams = [];
      sshUnlock = {
        # read sshUnlock.txt file.
        enable = false;
        authorizedKeys = [];
      };
    };
    networking = {
      # read changeHostName.txt file.
      hostName = "arachne";
      timeZone = "America/New_York";
      hostId = "16174aea";
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

  nix = {
    buildMachines = [
      {
        hostName = "zombie";
        systems = ["x86_64-linux" "aarch64-linux"];
        speedFactor = 2;
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
      }
    ];
    settings.max-jobs = 0;
    settings.trusted-users = ["collin"];
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
        experimental-features = nix-command flakes
    '';
  };

  networking.hostName = "arachne";
  networking.wireless.enable = true;
  networking.useDHCP = false;
  networking.interfaces.wlan0.useDHCP = true;

  time.timeZone = "America/New_York";

  programs.sway.enable = true;
  users.users.collin = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = ["wheel" "networkmanager" "video"];
  };
  programs.zsh.enable = true;
  programs.dconf.enable = true; # fixes issue with home-manager

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
  security.pam.services.swaylock = {};

  system.stateVersion = "21.11";
}
