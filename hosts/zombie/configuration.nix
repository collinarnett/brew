{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/cac.nix
    ../../modules/apcupsd.nix
    ../../modules/authelia.nix
    ../../modules/docker-registry.nix
    ../../modules/jellyfin.nix
    ../../modules/libvirtd.nix
    ../../modules/pipewire.nix
    ../../modules/searx.nix
    ../../modules/sops.nix
    ../../modules/syncthing.nix
    ../../modules/traefik.nix
    ../../modules/wireguard.nix
    ../../modules/xdg.nix
    ./hardware-configuration.nix
  ];

  services.cac.enable = true;

  # Editor
  services.emacs = {
    enable = true;
    defaultEditor = true;
    startWithGraphical = true;
  };

  # Bluetooth
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # Fonts
  fonts.packages = with pkgs; [
    emacs-all-the-icons-fonts
    fira-code
    fira-code-symbols
    siji
    noto-fonts-emoji
    nerdfonts
  ];

  # Remote Builds
  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  # General
  boot.loader.systemd-boot.configurationLimit = 30;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelModules = ["v4l2loopback" "amdgpu"];
  boot.extraModulePackages = [config.boot.kernelPackages.v4l2loopback];
  services.gvfs.enable = true;

  time.timeZone = "America/New_York";
  programs.zsh.enable = true;

  # Networking
  networking = {
    hostName = "zombie";
    nameservers = ["1.1.1.1" "9.9.9.9"];
    useDHCP = false;
    interfaces.enp10s0.useDHCP = true;
    interfaces.wlp8s0.useDHCP = true;
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
      ./authorized_keys.txt
    ];
  };

  programs.ssh.knownHosts = {
    hosts = {
      hostNames = ["github.com" "gitlab.com"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBmGJyuKh5/XGj2x6wZYxcS8krQZc74uBwMJaxeqaj8n collin@arnett.it";
    };
  };

  nix.settings.trusted-users = ["collin"];

  # Fixes 'too many open files'
  security.pam.loginLimits = [
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "4096";
    }
  ];

  documentation.dev.enable = true;

  # GPU
  hardware.graphics.enable = true;

  # Containers
  virtualisation.docker.enable = true;
  virtualisation.oci-containers.backend = "docker";

  # SSH
  services.openssh = {
    enable = true;
    ports = [6767];
    settings.PermitRootLogin = "yes";
    settings.PasswordAuthentication = false;
  };

  system.stateVersion = "21.11"; # Did you read the comment?
}
