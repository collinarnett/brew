{ config, pkgs, ... }:
{
  imports = [
    ./disko.nix
    ./impermanence.nix
  ];

  brew = {
    cac.enable = true;
    distributed-builds.enable = true;
    firefox.enable = true;
    greetd.enable = true;
    pipewire.enable = true;
    steam.enable = true;

    bat.enable = true;
    gh.enable = true;
    gtk.enable = true;
    kitty.enable = true;
    mako.enable = true;
    swayidle.enable = true;
    swaylock.enable = true;
    wofi.enable = true;
    zathura.enable = true;

    keychain = {
      enable = true;
      keys = [ "ghoul" ];
      extraFlags = [ ];
    };

    sway = {
      enable = true;
      outputs = {
        DP-3 = {
          position = "0 0";
          bg = "/home/collin/Pictures/purple_swamp.jpg fill";
        };
        eDP-1 = {
          transform = "normal";
          position = "0 1800";
          bg = "/home/collin/Pictures/purple_swamp.jpg fill";
        };
      };
      extraConfig = ''
        for_window [class=".*"] inhibit_idle fullscreen
        for_window [app_id=".*"] inhibit_idle fullscreen
        bindsym XF86MonBrightnessDown exec "brightnessctl set 2%-"
        bindsym XF86MonBrightnessUp exec "brightnessctl set +2%"
        bindsym XF86AudioMicMute exec pactl set-source-mute @DEFAULT_SOURCE@ toggle
        bindsym $mod+l exec ${pkgs.swaylock}/bin/swaylock
      '';
    };

    waybar = {
      enable = true;
      settings = {
        topBar = {
          output = "DP-3";
          position = "top";
          modules-left = [
            "cpu"
            "memory"
            "pulseaudio"
            "disk"
            "battery"
          ];
          modules-center = [ "sway/workspaces" ];
          modules-right = [ "clock" ];
          modules = {
            "sway/workspaces" = {
              persistent-workspaces = {
                "1" = [ ];
                "2" = [ ];
                "3" = [ ];
                "4" = [ ];
                "5" = [ ];
              };
              sort-by-number = [ ];
              format = "{icon}";
              format-icons = {
                default = "";
              };
            };
            "clock" = {
              format = " {:%I:%M}";
            };
            "cpu" = {
              format = " {usage}%";
            };
            "pulseaudio" = {
              format = " {volume}%";
            };
            "disk" = {
              format = " {percentage_used}%";
            };
            "mpd" = {
              format = " {title}";
            };
            "memory" = {
              format = " {used:0.1f}G";
            };
            "battery" = {
              format = "{icon}{capacity}%";
              states = {
                warning = 30;
                critical = 15;
              };
              format-icons = [
                ""
                ""
                ""
                ""
              ];
            };
          };
        };
        bottomBar = {
          output = "eDP-1";
          position = "bottom";
          modules-center = [ "sway/workspaces" ];
          modules-right = [ "clock" ];
          modules = {
            "sway/workspaces" = {
              persistent-workspaces = {
                "1" = [ ];
                "2" = [ ];
                "3" = [ ];
                "4" = [ ];
                "5" = [ ];
              };
              sort-by-number = [ ];
              format = "{icon}";
              format-icons = {
                default = "";
              };
              all-outputs = false;
            };
            "clock" = {
              format = " {:%I:%M}";
            };
          };
        };
      };
      style = ./waybar-style.css;
    };
  };

  # Ghoul-specific sops (different key paths from shared module)
  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  sops.age.keyFile = "/home/collin/.config/sops/age/keys.txt";
  sops.secrets.gh_token = {
    owner = config.users.users.collin.name;
  };

  services.emacs = {
    enable = true;
    startWithGraphical = true;
  };

  facter.reportPath = ./facter.json;

  boot.loader.systemd-boot.configurationLimit = 30;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.extraModprobeConfig = ''
    options bluetooth disable_ertm=Y
  '';

  fileSystems = {
    "/persist" = {
      device = "zroot/persist";
      fsType = "zfs";
      neededForBoot = true;
    };
    "/persist/save" = {
      device = "zroot/persistSave";
      fsType = "zfs";
      neededForBoot = true;
    };
  };

  networking.hostId = "b68778ef";

  boot = {
    kernelParams = [
      "nohibernate"
    ];
    initrd.systemd = {
      enable = true;
      services.rollback = {
        description = "Rollback ZFS datasets to a pristine state";
        serviceConfig.Type = "oneshot";
        unitConfig.DefaultDependencies = "no";
        wantedBy = [ "initrd.target" ];
        after = [ "zfs-import-zroot.service" ];
        requires = [ "zfs-import-zroot.service" ];
        before = [ "sysroot.mount" ];
        path = with pkgs; [ zfs ];
        script = ''
          zfs rollback -r zroot/root@empty && echo "rollback complete"
        '';
      };
      services.create-needed-for-boot-dirs = {
        after = pkgs.lib.mkForce [ "rollback.service" ];
        wants = pkgs.lib.mkForce [ "rollback.service" ];
      };
    };
    initrd.supportedFilesystems.zfs = true;
    supportedFilesystems = [
      "vfat"
      "zfs"
    ];
    zfs = {
      forceImportAll = true;
    };
  };

  hardware.graphics.enable = true;
  services.tlp = {
    enable = true;
    settings = {
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 80;

      CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
      CPU_SCALING_GOVERNOR_ON_BAT = "schedutil";

      CPU_SCALING_MIN_FREQ_ON_AC = 800000;
      CPU_SCALING_MAX_FREQ_ON_AC = 3500000;
      CPU_SCALING_MIN_FREQ_ON_BAT = 800000;
      CPU_SCALING_MAX_FREQ_ON_BAT = 2300000;

      SOUND_POWER_SAVE_ON_AC = 0;
      SOUND_POWER_SAVE_ON_BAT = 1;

      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";

      NATACPI_ENABLE = 1;
      TPACPI_ENABLE = 1;
      TPSMAPI_ENABLE = 1;
    };
  };

  networking.hostName = "ghoul";
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.scanRandMacAddress = false;

  time.timeZone = "America/New_York";

  users.users.collin = {
    isNormalUser = true;
    shell = pkgs.zsh;
    hashedPassword = "$y$j9T$x.RDCNGwrERU4QtCPXuGB1$5hKCIlIQvWLFTiMI90EOCARUWWqUFDS2oXdYI8JrLe3";
    openssh.authorizedKeys.keyFiles = [
      ../../secrets/keys/collinarnett.pub
    ];
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
    ];
  };
  programs.zsh.enable = true;
  programs.dconf.enable = true;

  services.blueman.enable = true;
  environment.systemPackages = with pkgs; [
    adwaita-icon-theme
    hunspellDicts.en_US
    wget
    git
    brightnessctl
  ];
  environment.sessionVariables = {
    GPG_TTY = "$(tty)";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  services.openssh.enable = true;

  # Home-manager user config
  home-manager.users.${config.brew.user} = {
    home.username = "collin";
    home.homeDirectory = "/home/collin";
    home.sessionVariables = {
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
      GPG_TTY = "$(tty)";
    };

    home.packages = with pkgs; [
      anki-bin
      bluetui
      claude-code
      chromium
      croc
      drawio
      emacs-all-the-icons-fonts
      fira-code
      fira-code-symbols
      forge-mtg
      git
      gotop
      grim
      helvum
      imv
      libreoffice
      neofetch
      noto-fonts-color-emoji
      openconnect
      pandoc
      pavucontrol
      poppler-utils
      pulseaudio
      ripgrep
      signal-desktop
      siji
      slurp
      thunderbird
      tree
      unzip
      wl-clipboard
      xournalpp
    ];

    home.stateVersion = "21.11";
    programs.home-manager.enable = true;
  };

  system.stateVersion = "24.11";
}
