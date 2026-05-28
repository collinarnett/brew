{ config, pkgs, lib, ... }:
{
  imports = [
    ./disko.nix
    ./impermanence.nix
  ];

  # ── Brew Module Configuration ─────────────────────────────────────

  brew = {
    common.enable = true;
    desktop.enable = true;
    laptop.enable = true;
    claude-code.enable = true;

    swayidle.enableDpms = false;

    chromium = {
      enable = true;
      whisperlivekit.serverUrl = "ws://localhost:8010/asr";
    };

    keychain = {
      keys = [ "ghoul" ];
      extraFlags = [ ];
    };

    sway = {
      modifier = "Mod1";
      outputs = {
        DP-3 = {
          position = "0 0";
          bg = "/home/collin/Pictures/purple_swamp.jpg fill";
        };
        eDP-1 = {
          transform = "normal";
          position = "0 900";
          bg = "/home/collin/Pictures/purple_swamp.jpg fill";
        };
      };
      focusWorkspace = "9";
      # Top monitor (DP-3): workspaces 6 7 8 9 10
      # Bottom monitor (eDP-1): workspaces 1 2 3 4 5
      # sway maps $mod+0 to "workspace number 10", not "workspace number 0"
      workspaces =
        let
          top = { output = "DP-3"; };
          bottom = { output = "eDP-1"; };
        in
        {
          "10" = top // {
            assigns = [
              { class = "^Emacs$"; }
              { app_id = "^emacs$"; }
            ];
            startup = [
              {
                command = "waypipe ssh -X azathoth emacs";
                requiresInternet = true;
                waitFor = "emacs";
              }
            ];
          };
          "1" = bottom // {
            startup = [
              {
                command = "waypipe ssh -X azathoth firefox-esr";
                preCommand = "/run/current-system/sw/bin/ssh azathoth 'pkill -f /firefox-esr || true' 2>/dev/null; sleep 1";
                requiresInternet = true;
                waitFor = "firefox";
              }
            ];
          };
          "2" = bottom // {
            startup = [
              {
                command = "${pkgs.firefox-esr}/bin/firefox-esr";
                waitFor = "firefox";
              }
            ];
          };
          "3" = bottom;
          "4" = bottom;
          "5" = bottom;
          "6" = top;
          "7" = top;
          "8" = top;
          "9" = top // {
            startup = [
              {
                command = "kitty";
                waitFor = "kitty";
              }
            ];
          };
        };
      extraConfig = ''
        for_window [class=".*"] inhibit_idle fullscreen
        for_window [app_id=".*"] inhibit_idle fullscreen
        bindsym --locked XF86MonBrightnessDown exec "brightnessctl set 2%-"
        bindsym --locked XF86MonBrightnessUp exec "brightnessctl set +2%"
        bindsym --locked XF86AudioMicMute exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
        unbindsym $mod+l
        bindsym $mod+l exec ${pkgs.swaylock}/bin/swaylock
      '';
    };

    waybar = {
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
          modules-right = [ "custom/tomat" "clock" ];
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
                default = "";
              };
            };
            "clock" = {
              format = " {:%I:%M}";
            };
            "cpu" = {
              format = " {usage}%";
            };
            "pulseaudio" = {
              format = " {volume}%";
            };
            "disk" = {
              format = " {percentage_used}%";
            };
            "mpd" = {
              format = " {title}";
            };
            "memory" = {
              format = " {used:0.1f}G";
            };
            "battery" = {
              format = "{icon}{capacity}%";
              states = {
                warning = 30;
                critical = 15;
              };
              format-icons = [
                ""
                ""
                ""
                ""
              ];
            };
            "custom/tomat" = {
              exec = "tomat status";
              interval = 1;
              return-type = "json";
              format = "{}";
              on-click = "tomat toggle";
              on-click-right = "tomat skip";
            };
          };
        };
        bottomBar = {
          output = "eDP-1";
          position = "bottom";
          modules-left = [ "battery" ];
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
                default = "";
              };
              all-outputs = false;
            };
            "clock" = {
              format = " {:%I:%M}";
            };
          };
        };
      };
      style = ./waybar-style.css;
    };
  };

  # ── Boot & Storage ────────────────────────────────────────────────

  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 30;
      };
      efi.canTouchEfiVariables = true;
    };
    extraModprobeConfig = ''
      options bluetooth disable_ertm=Y
    '';
    kernelParams = [
      "nohibernate"
    ];
    initrd = {
      supportedFilesystems.zfs = true;
      systemd = {
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
    };
    supportedFilesystems = [
      "vfat"
      "zfs"
    ];
    zfs.forceImportAll = true;
  };

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

  systemd.services.trackpad-rebind = {
    description = "Rebind SP3105FT touchpad I2C HID";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'echo i2c-SP3105FT:00 > /sys/bus/i2c/drivers/i2c_hid_acpi/unbind && sleep 1 && echo i2c-SP3105FT:00 > /sys/bus/i2c/drivers/i2c_hid_acpi/bind'";
    };
  };

  # ── Networking ────────────────────────────────────────────────────

  networking = {
    hostName = "ghoul";
    hostId = "b68778ef";
    networkmanager = {
      enable = true;
      wifi.scanRandMacAddress = false;
    };
  };

  # ── Hardware ──────────────────────────────────────────────────────

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

  # ── Users ─────────────────────────────────────────────────────────

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
  programs.ssh.setXAuthLocation = true;

  # ── Services ──────────────────────────────────────────────────────

  services.emacs = {
    enable = true;
    startWithGraphical = true;
  };

  services.blueman.enable = true;

  brew.gh-token.enable = true;

  # ── Packages & Environment ────────────────────────────────────────

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

  # ── System ────────────────────────────────────────────────────────

  time.timeZone = "America/New_York";
  facter.reportPath = ./facter.json;
  system.stateVersion = "24.11";

  # ── Home Manager ──────────────────────────────────────────────────

  home-manager.users.${config.brew.user} = {
    home.username = "collin";
    home.homeDirectory = "/home/collin";
    home.sessionVariables = {
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
      GH_TOKEN = "$(cat ${config.clan.core.vars.generators.gh_token.files.gh_token.path})";
      GPG_TTY = "$(tty)";
    };

    home.packages = with pkgs; [
      bluetui

      croc
      emacs-all-the-icons-fonts
      fira-code
      fira-code-symbols
      forge-mtg
      git
      gotop
      grim
      noto-fonts-color-emoji
      pavucontrol
      poppler-utils
      siji
      slurp
    ];

    home.stateVersion = "21.11";
    programs.home-manager.enable = true;
  };
}
