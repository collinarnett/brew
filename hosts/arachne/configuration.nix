{ config, pkgs, ... }:

{
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/pipewire.nix
    ./modules/sops.nix
  ];

  # Flakes
  nix = {
    package = pkgs.nixUnstable;
    # Arachne is not very powerful so we use Zombie to build it's packages
    buildMachines = [{
      hostName = "zombie";
      systems = [ "x86_64-linux" "aarch64-linux" "i686-linux" ];
      maxJobs = 1;
      speedFactor = 2;
      supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
    }];
    settings.trusted-users = [ "collin" ];
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
      experimental-features = nix-command flakes
    '';
  };

  # Arachne uses Tow-Boot
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  networking.hostName = "arachne"; 
  networking.networkmanager.enable = true;

  time.timeZone = "America/New_York";

  networking.useDHCP = false;
  networking.interfaces.wlan0.useDHCP = true;

  programs.vim.defaultEditor = true;
  users.users.collin = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups =
      [ "wheel" "networkmanager" "video" ]; 
  };

  environment.systemPackages = with pkgs; [ vim wget git ];

  services.openssh.enable = true;

  system.stateVersion = "21.11";

}

