{ config, pkgs, ... }:

{
  imports = [ # Include the results of the hardware scan.
    ../../modules/apcupsd.nix
    ../../modules/docker/authelia/authelia.nix
    ../../modules/docker/navidrome.nix
    ../../modules/docker/searx.nix
    ../../modules/docker/watchtower.nix
    ../../modules/libvirtd.nix
    ../../modules/pipewire.nix
    ../../modules/sops.nix
    ../../modules/taskserver.nix
    ../../modules/traefik.nix
    ../../modules/k3s.nix
    ./hardware-configuration.nix
  ];

  # Flakes
  nix.package = pkgs.nixFlakes;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Remote Builds
  boot.binfmt.emulatedSystems = [ "aarch64-linux" "i686-linux" ];

  # General
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "zombie"; # Define your hostname.

  time.timeZone = "America/New_York";
  programs.vim.defaultEditor = true;

  # Networking
  networking.useDHCP = false;
  networking.interfaces.enp10s0.useDHCP = true;
  networking.interfaces.wlp8s0.useDHCP = true;

  # Users
  users.users.collin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "libvirtd" "input" "audio" "docker" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC9+hfX1OTMC1AeAj0noGcrdVGjgWoYBjREwHbIybKAezRQGwKmrwy9C3ussdk3Xmggc3K2tIR6UxAGLtFaBFC+OMK1Se8KwNgKRHxJVAfphCP9GS/rFb30o/NJvHue25BI+j8qGQBvsLXO/drCbIsPv6PmknOlGHcto6hfZe+6Kp4OXp9Mdmd4y3Kr7YcKIWu7rVHoi8b0EG20+KIHXX7wc0KoJIjHSJOjjtWqukaaXwG2mFkoB94juyWVp1zYztZcuyenYNSKYiANuiUmf7M80PDF0wIK6+sMtAP3q5wHLNExvs6BVLMFNlkjcfq6xWcwJraxDqqYhl0GA89o8tlvCGaKn/hQK0EnTdl3BdX6/i/WmSH8G6FMoKQBIu0tI3tSkS9JNvpGWjr6Wwp+fb9oVEmpXItHc2gksaNWhhM3UdMOds6IH+hkxzrTNVS/9F8dOVrp9n7uPvCDQD+um9BQsuM+lw7e+Uce9QlxrA5mJx6zC4CG4gpqfLAoSe+eybQNj33NPRJ5LnP20YWzq5AHQF3A3HV3UgbjciGQEykzGzeKI7+9QmtRcKy19TDTe09lY3Xmq+eTxFJCtqIzxHF8s5UgNUY1oJP9gR4228mqDPk/+Uzr0xfE0UnEijbbtLlNl/eJh0MOkb1ifPaQSIqpiniuDacGmW0t51lcGFUYKQ== collin@arnett.it"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH19yqg2Li7CSHG1JBlFJM1lK484uqAhEqzkSrfuyadu Work Macbook"
    ];
  };

  nix.settings.trusted-users = [ "collin" ];

  # GPU
  hardware.opengl = {
    enable = true;
    driSupport = true;
  };

  # Containers
  virtualisation.docker.enable = true;
  environment.systemPackages = [ pkgs.docker-compose ];
  virtualisation.oci-containers.backend = "docker";

  # SSH
  services.openssh = {
    enable = true;
    ports = [ 6767 ];
    permitRootLogin = "no";
    passwordAuthentication = false;
  };

  system.stateVersion = "21.11"; # Did you read the comment?
}

