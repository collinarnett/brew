{ config, pkgs, ... }:

{
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./modules/apcupsd.nix
    ./modules/ddclient.nix
    ./modules/libvirtd.nix
    ./modules/pipewire.nix
    ./modules/searx.nix
    ./modules/sops.nix
  ];

  # Flakes
  nix.package = pkgs.nixFlakes;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

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
    extraGroups = [ "wheel" "libvirtd" "input" "audio" ];
    shell = pkgs.zsh;
  };

  # GPU
  hardware.opengl = {
    enable = true;
    driSupport = true;
  };

  # Containers
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
    };
  };

  # SSH
  services.openssh.enable = true;

  system.stateVersion = "21.11"; # Did you read the comment?
}

