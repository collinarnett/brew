{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "witch";

  #
  # Opinionated defaults
  #
  
  # Use Network Manager
  networking.wireless.enable = false;
  networking.networkmanager.enable = true;
  
  # Use PulseAudio
  hardware.pulseaudio.enable = true;
  
  # Enable Bluetooth
  hardware.bluetooth.enable = true;
  
  # Bluetooth audio
  hardware.pulseaudio.package = pkgs.pulseaudioFull;
  
  # Enable power management options
  powerManagement.enable = true;
  
  # It's recommended to keep enabled on these constrained devices
  zramSwap.enable = true;

  # Auto-login for phosh
  services.xserver.desktopManager.phosh = {
    user = "collin";
  };

  #
  # User configuration
  #
  
  users.users."collin" = {
    isNormalUser = true;
    description = "Collin";
    hashedPassword = "$6$Ng9jucjg4mBYy56O$Pk5MKKzl4BQMul/hSHbNJti1JbV.mnWBP8pWohJ.EGIpIHK8KYVsDjyFXkebekk2MnXZ9jAU/8x9bme0PJ/6V0";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBmGJyuKh5/XGj2x6wZYxcS8krQZc74uBwMJaxeqaj8n collin@arnett.it"
      ];
    extraGroups = [
      "dialout"
      "feedbackd"
      "networkmanager"
      "video"
      "wheel"
    ];
  };

  time.timeZone = "America/New_York";

    nix = {
      gc = {
        automatic = true;
        options = "--delete-older-than 8d";
      };
      settings.trusted-users = [ "collin" ];
      buildMachines = [{
        hostName = "zombie";
        systems = [ "x86_64-linux" "aarch64-linux" ];
        maxJobs = 1;
        speedFactor = 2;
        supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
      }];
      distributedBuilds = true;

      # nix flakes
      package = pkgs.nixUnstable;
      extraOptions = ''
        builders-use-substitutes = true
        experimental-features = nix-command flakes
      '';
    };

  programs.vim.defaultEditor = true;
  environment.systemPackages = with pkgs; [ git vim wget ];
  
  services.openssh = {
    enable = true;
    passwordAuthentication = true;
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11"; # Did you read the comment?
}
