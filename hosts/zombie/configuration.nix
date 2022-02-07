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
    ../../modules/traefik.nix
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
  };

  nix.trustedUsers = [ "collin" ];

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
  services.openssh.enable = true;

  system.stateVersion = "21.11"; # Did you read the comment?
}

