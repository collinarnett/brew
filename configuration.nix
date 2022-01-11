{ config, pkgs, ... }:

{
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./modules/ddclient.nix
  ];
  nix.package = pkgs.nixFlakes;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "zombie"; # Define your hostname.

  time.timeZone = "America/New_York";

  networking.useDHCP = false;
  networking.interfaces.enp1s0.useDHCP = true;

  sound.enable = true;
  hardware.pulseaudio = {
    enable = true;
    extraConfig =
      "load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1";
  };

  users.users.collin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; 
    shell = pkgs.zsh;
  };

  sops.defaultSopsFile = ./secrets/secrets.yaml;
  sops.age.keyFile = "/home/collin/.config/sops/age/keys.txt";
  sops.secrets.awscli2-config = { };
  sops.secrets.awscli2-credentials = { };
  sops.secrets.ddclient-config = { };

  hardware.opengl = {
    enable = true;
    driSupport = true;
  };

  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
    };
  };

  programs.vim.defaultEditor = true;
  services.openssh.enable = true;

  system.stateVersion = "21.11"; # Did you read the comment?
}

