{ config, lib, pkgs, ... }:

let hostName = "pinephone";
in {

  imports = [ ];
  config = {
    nixpkgs.system = "aarch64-linux";
    users.users.collin = {
      isNormalUser = true;
      home = "/home/collin";
      shell = pkgs.zsh;
      createHome = true;
      extraGroups = [ "wheel" "networkmanager" "video" "feedbackd" "dialout" ];
      uid = 1000;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBmGJyuKh5/XGj2x6wZYxcS8krQZc74uBwMJaxeqaj8n collin@arnett.it"
      ];
      password = "nixos";
    };
    users.users.root.password = "nixos";
    powerManagement.enable = true;
    hardware.opengl = { enable = true; };
    programs.vim.defaultEditor = true;
    time.timeZone = "America/New_York";

    # Pkgs
    environment.systemPackages = with pkgs; [ git wget ];

    environment.etc."machine-info".text = lib.mkDefault ''
      CHASSIS="handset"
    '';

    ##########################################################################
    ## networking, modem and misc.
    ##########################################################################

    networking = {
      inherit hostName;

      wireless.enable = false;
      networkmanager.enable = true;

      # FIXME : configure usb rndis through networkmanager in the future.
      # Currently this relies on stage-1 having configured it.
      networkmanager.unmanaged = [ "rndis0" "usb0" ];
    };

    # Setup USB gadget networking in initrd...
    mobile.boot.stage-1.networking.enable = lib.mkDefault true;

    # Bluetooth
    hardware.bluetooth.enable = true;

    ##########################################################################
    ## SSH
    ##########################################################################

    services.openssh = {
      enable = true;
      passwordAuthentication = false;
      permitRootLogin = "no";
      allowSFTP = false;
    };

    programs.mosh.enable = true;

    # Don't start it in stage-1 though.
    # (Currently doesn't quit on switch root)
    # mobile.boot.stage-1.ssh.enable = true;

    ##########################################################################
    # default quirks
    ##########################################################################

    # Ensures this demo rootfs is useable for platforms requiring FBIOPAN_DISPLAY.
    mobile.quirks.fb-refresher.enable = true;

    # Okay, systemd-udev-settle times out... no idea why yet...
    # Though, it seems fine to simply disable it.
    # FIXME : figure out why systemd-udev-settle doesn't work.
    systemd.services.systemd-udev-settle.enable = false;

    # Force userdata for the target partition. It is assumed it will not
    # fit in the `system` partition.
    mobile.system.android.system_partition_destination = "userdata";

    ##########################################################################
    ## misc "system"
    ##########################################################################

    # No mutable users. This requires us to set passwords with hashedPassword.
    users.mutableUsers = false;

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

    # This value determines the NixOS release with which your system is to be
    # compatible, in order to avoid breaking some software such as database
    # servers. You should change this only after NixOS release notes say you
    # should.
    system.stateVersion = "21.11"; # Did you read the comment?

  };

}
