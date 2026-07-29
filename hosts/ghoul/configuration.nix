{
  config,
  pkgs,
  lib,
  ...
}:
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
        # Any external display on the HDMI port, extended to the right of the
        # 1440px-wide laptop stack. The scale here is the fallback for a display
        # that is connected at login; the hdmi-autoscale service below adjusts
        # it to match the panel's resolution on every hotplug (4K -> 2x).
        HDMI-A-1 = {
          position = "1440 0";
          scale = "1";
          bg = "/home/collin/Pictures/purple_swamp.jpg fill";
        };
      };
      focusWorkspace = "9";
      # Top monitor (DP-3): workspaces 8 9 10
      # Bottom monitor (eDP-1): workspaces 1 2 3 4 5
      # HDMI TV (HDMI-A-1): workspaces 6 7
      # sway maps $mod+0 to "workspace number 10", not "workspace number 0"
      workspaces =
        let
          top = {
            output = "DP-3";
          };
          bottom = {
            output = "eDP-1";
          };
          tv = {
            output = "HDMI-A-1";
          };
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
          "6" = tv;
          "7" = tv;
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
          modules-right = [
            "custom/tomat"
            "clock"
          ];
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

    brew.radicle.enable = true;

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

    # blueman-applet requires tray.target, but waybar (which hosts the tray) is
    # launched from sway's bar config, so nothing starts tray.target on its own.
    # Bind it to the graphical session so the applet can start.
    services.blueman-applet.enable = true;
    systemd.user.targets.tray.Install.WantedBy = [ "graphical-session.target" ];

    # Scale the HDMI output to match whatever panel is plugged in. Sway keys
    # output config by connector name, so a static scale cannot serve both a 4K
    # display (wants 2x) and a 1080p one (wants 1x) on the same port. This
    # watches sway's output events and picks the scale from the live resolution,
    # so any monitor or TV gets a sensible size on hotplug without per-panel config.
    systemd.user.services.hdmi-autoscale = {
      Unit = {
        Description = "Scale the HDMI output to match the connected panel's resolution";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${
          pkgs.writeShellApplication {
            name = "hdmi-autoscale";
            runtimeInputs = with pkgs; [
              sway
              jq
            ];
            text = ''
              apply() {
                local w h s want cur
                read -r w h s < <(
                  swaymsg -t get_outputs \
                    | jq -r '.[] | select(.name == "HDMI-A-1" and .active) | "\(.current_mode.width) \(.current_mode.height) \(.scale)"'
                ) || true
                [ -n "''${w:-}" ] || return 0
                if [ "$w" -ge 3840 ] || [ "$h" -ge 2160 ]; then
                  want=2
                else
                  want=1
                fi
                cur=$(printf '%.0f' "$s")
                [ "$cur" = "$want" ] || swaymsg output HDMI-A-1 scale "$want"
              }

              apply
              swaymsg -t subscribe -m '["output"]' | while read -r _; do
                apply
              done
            '';
          }
        }/bin/hdmi-autoscale";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "sway-session.target" ];
    };

    home.stateVersion = "21.11";
    programs.home-manager.enable = true;
  };
}
