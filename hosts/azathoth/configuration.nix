{
  pkgs,
  config,
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
    server.enable = true;

    claude-code.enable = true;
    beets.enable = true;
    k9s.enable = true;
    pcie-passthrough = {
      enable = true;
      user = "collin";
      platform = "amd";
      vfio-ids = [
        "10de:2204"
        "10de:1aef"
      ];
    };

    homelab = {
      searx.enable = true;
      traefik.enable = true;
      authelia.enable = true;
      jellyfin.enable = true;
      calibre-web.enable = true;
    };

    keychain = {
      keys = [
        "id_ed25519"
        "clan-gitea"
      ];
      extraFlags = [ "--systemd" ];
    };
    gh-token.enable = true;
    sway.outputs = {
      DP-4 = {
        bg = "${../../modules/sway/blackhole.jpg} fill";
        subpixel = "none";
        scale = "2";
      };
    };
    chromium = {
      enable = true;
      whisperlivekit.serverUrl = "ws://192.168.122.132:8010/asr";
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

  # ── Networking ────────────────────────────────────────────────────

  networking = {
    hostName = "azathoth";
    hostId = "20556d4b";
    nameservers = [
      "1.1.1.1"
      "9.9.9.9"
    ];
    hosts = {
      "127.0.0.1" = [
        "kubernetes"
      ];
    };
  };

  # ── Hardware ──────────────────────────────────────────────────────

  hardware.graphics.enable = true;

  # ── Users ─────────────────────────────────────────────────────────

  users.users.collin = {
    isNormalUser = true;
    extraGroups = [
      "video"
      "wheel"
      "libvirtd"
      "input"
      "audio"
      "docker"
      "adbusers"
      "multimedia"
      "aws"
    ];
    shell = pkgs.zsh;
    hashedPassword = "$y$j9T$x.RDCNGwrERU4QtCPXuGB1$5hKCIlIQvWLFTiMI90EOCARUWWqUFDS2oXdYI8JrLe3";
    openssh.authorizedKeys.keyFiles = [
      ../../secrets/keys/collinarnett.pub
      ../../secrets/keys/ghoul.pub
    ];
  };

  programs.zsh.enable = true;
  programs.ssh.setXAuthLocation = true;

  # ── Services ──────────────────────────────────────────────────────

  services.emacs = {
    enable = true;
    defaultEditor = true;
    startWithGraphical = true;
  };

  services.openssh = {
    enable = true;
    ports = [ 8787 ];
    settings.X11Forwarding = true;
    settings.PermitRootLogin = "yes";
  };

  virtualisation.docker.enable = true;
  virtualisation.oci-containers.backend = "docker";

  documentation.dev.enable = true;

  # ── Nix Settings ──────────────────────────────────────────────────

  nix.settings = {
    trusted-users = [ "collin" ];
    netrc-file = "/etc/nix/netrc";
    extra-sandbox-paths = [
      "/etc/nix/netrc"
    ];
  };

  # ── Programs & Packages ───────────────────────────────────────────

  programs.obs-studio.enable = true;
  programs.tmux.enable = true;
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake = "/home/collin/brew";
  };
  programs.kdeconnect.enable = true;

  # ── System ────────────────────────────────────────────────────────

  time.timeZone = "America/New_York";
  facter.reportPath = ./facter.json;
  system.stateVersion = "24.11";

  # ── Home Manager ──────────────────────────────────────────────────

  home-manager.users.${config.brew.user} = {
    home.username = "collin";
    home.homeDirectory = "/home/collin";
    home.sessionVariables = {
      GH_TOKEN = "$(cat ${config.clan.core.vars.generators.gh_token.files.gh_token.path})";
      GPG_TTY = "$(tty)";
    };

    home.packages = with pkgs; [
      alejandra
      anki-bin
      bash-language-server
      bibata-cursors
      clang-tools

      cloc
      crawl
      dconf
      drawio
      electron_38
      fastfetch
      fd
      freetube
      graphviz
      hledger
      httpie
      hunspellDicts.en_US
      imv
      iommu-groups
      jq
      languagetool
      leiningen
      libreoffice
      nixd
      nix-output-monitor
      nix-tree
      nixfmt
      nixpkgs-review
      pandoc
      pciutils
      pinta
      pulseaudio
      ripgrep
      ruff
      signal-desktop
      statix
      tealdeer
      texliveFull
      timg
      tree
      unzip
      usbutils
      waypipe
      wget
      whipper
      wl-clipboard
      xauth
      xplr
      zip
    ];

    home.stateVersion = "24.11";
    programs.home-manager.enable = true;
  };
}
