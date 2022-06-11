{ config, pkgs, ... }:

{
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/pipewire.nix
    ../../modules/greetd.nix
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
    extraGroups = [ "wheel" "networkmanager" "video" ];
  };

  environment.systemPackages = with pkgs; [ vim wget git brightnessctl ];
  environment.sessionVariables = {
    GPG_TTY = "$(tty)";
    WLR_NO_HARDWARE_CURSORS = "1";
    GH_TOKEN = "$(cat ${config.sops.secrets.gh_token.path})";
  };

  services.openssh.enable = true;
  security.pam.services.swaylock = { };

  system.stateVersion = "21.11";

}

