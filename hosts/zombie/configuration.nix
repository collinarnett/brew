{
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/apcupsd.nix
    ../../modules/cac.nix
    ../../modules/docker-registry.nix
    ../../modules/homelab.nix
    ../../modules/pipewire.nix
    ../../modules/sops.nix
    ../../modules/wireguard.nix
    ../../modules/xdg.nix
    ./hardware-configuration.nix
  ];

  # Homelab
  services.homelab = {
    enable = true;
    authelia.enable = true;
    searx.enable = true;
    traefik.enable = true;
    jellyfin.enable = true;
  };

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
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKkZxQik8yzR4f1G+co2pnh/jLrE72XaJbdkNsVpPix0 collin@zombie"
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

  nix.settings.trusted-users = ["collin"];

  # Man pages
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
