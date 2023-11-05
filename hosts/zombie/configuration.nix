{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/apcupsd.nix
    ../../modules/dwarf-fortress.nix
    ../../modules/syncthing.nix
    ../../modules/libvirtd.nix
    ../../modules/pipewire.nix
    ../../modules/sops.nix
    ../../modules/taskserver.nix
    ../../modules/wireguard.nix
    ../../modules/xdg.nix
    ../../modules/calibre-web.nix
    ./hardware-configuration.nix
  ];

  # Flakes
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  services.emacs = {
    enable = true;
    defaultEditor = true;
    startWithGraphical = true;
    package = (import ../../modules/emacs/emacs.nix) pkgs;
  };

  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    randomizedDelaySec = "14m";
    options = "--delete-older-than 10d";
  };

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # Remote Builds
  boot.binfmt.emulatedSystems = ["aarch64-linux" "i686-linux"];

  # General
  boot.loader.systemd-boot.configurationLimit = 30;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelModules = ["v4l2loopback" "amdgpu"];
  boot.extraModulePackages = [config.boot.kernelPackages.v4l2loopback];
  services.gvfs.enable = true;
  networking.hostName = "zombie"; # Define your hostname.
  networking.nameservers = ["1.1.1.1" "9.9.9.9"];

  time.timeZone = "America/New_York";
  programs.zsh.enable = true;

  # Networking
  networking.useDHCP = false;
  networking.interfaces.enp10s0.useDHCP = true;
  networking.interfaces.wlp8s0.useDHCP = true;

  # Users
  users.users.collin = {
    isNormalUser = true;
    extraGroups = ["wheel" "libvirtd" "input" "audio" "docker" "adbusers"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC9+hfX1OTMC1AeAj0noGcrdVGjgWoYBjREwHbIybKAezRQGwKmrwy9C3ussdk3Xmggc3K2tIR6UxAGLtFaBFC+OMK1Se8KwNgKRHxJVAfphCP9GS/rFb30o/NJvHue25BI+j8qGQBvsLXO/drCbIsPv6PmknOlGHcto6hfZe+6Kp4OXp9Mdmd4y3Kr7YcKIWu7rVHoi8b0EG20+KIHXX7wc0KoJIjHSJOjjtWqukaaXwG2mFkoB94juyWVp1zYztZcuyenYNSKYiANuiUmf7M80PDF0wIK6+sMtAP3q5wHLNExvs6BVLMFNlkjcfq6xWcwJraxDqqYhl0GA89o8tlvCGaKn/hQK0EnTdl3BdX6/i/WmSH8G6FMoKQBIu0tI3tSkS9JNvpGWjr6Wwp+fb9oVEmpXItHc2gksaNWhhM3UdMOds6IH+hkxzrTNVS/9F8dOVrp9n7uPvCDQD+um9BQsuM+lw7e+Uce9QlxrA5mJx6zC4CG4gpqfLAoSe+eybQNj33NPRJ5LnP20YWzq5AHQF3A3HV3UgbjciGQEykzGzeKI7+9QmtRcKy19TDTe09lY3Xmq+eTxFJCtqIzxHF8s5UgNUY1oJP9gR4228mqDPk/+Uzr0xfE0UnEijbbtLlNl/eJh0MOkb1ifPaQSIqpiniuDacGmW0t51lcGFUYKQ== collin@arnett.it"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH19yqg2Li7CSHG1JBlFJM1lK484uqAhEqzkSrfuyadu Work Macbook"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDuX/Vf5RGrzsGTXy+yghJpQ6iO38FPncnmlOB6cEVWt+2nJyVISh6nMdzfqP+Xuro/Xv2loWmmXRo3Rmh6ahZtuSf6sUK+TGIXqF/u0OrZKFXVT8gITGxYPSOSXr8lVYnxx3lcAuC+UQu5XLhy9ksfwmtA8PZlsm5uI1hfcM+pnBM+dDQx+91aTfn5iGxl4bQ4MCfWYEFjrM99ZkSX+V+uxjBZbO7z6rffsmP4J1/t39k5EBBXllVNP2m3wWl8huyuTPi5ODt8yoPk5akLfPZa7YPUF1nwQGpl2dGmLktEbN5WhpZDjZPMbeJAHqYwyMTZoTIg14zlqsEv9m31+Y+t8uFF9A+5QbQnqIk1PlLVRZLz6OAvGrC22Xuh0VjA7tMf0RgGJSmCBbauzCkiwUWu2qvJDgzybY4qZnx1JiD3zI2n0b0RVWyl54/GX3+gnX+pI7X46pMFaKVweY3mzqDQqMtdScbMrUKQYAEdHvpRw2gB4PyrUhsZWVX3B4PCfLU= collin@pinephone"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIClMw0Z3hxV0Ai0MchCcTFOm7yE89feP98rUCO1EHkVN collin@arachne"
    ];
  };

  programs.ssh.knownHosts = {
    hosts = {
      hostNames = ["github.com" "gitlab.com"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBmGJyuKh5/XGj2x6wZYxcS8krQZc74uBwMJaxeqaj8n collin@arnett.it";
    };
  };

  services.udev.packages = with pkgs; [
    android-udev-rules
    qmk-udev-rules
    vial
  ];

  services.udev.extraRules = ''
    'KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0666", TAG+="uaccess", TAG+="udev-acl"'
  '';

  environment.systemPackages = with pkgs; [
    vial
  ];

  nix.settings.trusted-users = ["collin"];

  # Binary Caches
  nix.settings.substituters = ["https://cache.nixos.org/"];
  nix.settings.trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];

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

  programs.adb.enable = true;

  # GPU
  hardware.opengl = {
    enable = true;
    driSupport = true;
  };

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
