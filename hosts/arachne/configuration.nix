{pkgs, ...}: {
  imports = [
    ../../modules/pipewire.nix
    ../../modules/greetd.nix
    ./modules/sops.nix
  ];

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

  hardware.opengl.enable = true;
  # Flakes
  nix = {
    buildMachines = [
      {
        hostName = "zombie";
        systems = ["x86_64-linux" "aarch64-linux"];
        speedFactor = 2;
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
      }
    ];
    settings.max-jobs = 1;
    settings.trusted-users = ["collin"];
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
      experimental-features = nix-command flakes
    '';
  };

  # Bluetooth
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  networking.hostName = "arachne";
  networking.networkmanager.enable = true;

  time.timeZone = "America/New_York";

  networking.useDHCP = false;
  networking.interfaces.wlan0.useDHCP = true;

  programs.sway.enable = true;
  programs.vim.defaultEditor = true;
  users.users.collin = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = ["wheel" "networkmanager" "video"];
  };
  programs.zsh.enable = true;
  programs.dconf.enable = true; # fixes issue with home-manager

  environment.systemPackages = with pkgs; [
    gnome.adwaita-icon-theme
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
