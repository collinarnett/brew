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

  brew = {
    apcupsd.enable = true;
    atticd.enable = true;
    cac.enable = true;
    docker-registry.enable = true;
    firefox.enable = true;
    greetd.enable = true;
    pipewire.enable = true;
    remote-build.enable = true;
    restic.enable = true;
    sops.enable = true;
    xdg-portal.enable = true;

    homelab = {
      enable = true;
      searx.enable = true;
      traefik.enable = true;
      authelia.enable = true;
      jellyfin.enable = true;
      calibre-web.enable = true;
    };

    pcie-passthrough = {
      enable = true;
      user = "collin";
      platform = "amd";
      vfio-ids = [
        "10de:2204"
        "10de:1aef"
      ];
    };

    # Home-manager feature modules
    autojump.enable = true;
    bat.enable = true;
    beets.enable = true;
    fzf.enable = true;
    gh.enable = true;
    gtk.enable = true;
    k9s.enable = true;
    kitty.enable = true;
    mako.enable = true;
    wofi.enable = true;
    xdg-mime.enable = true;
    zathura.enable = true;
    zoxide.enable = true;

    keychain = {
      enable = true;
      keys = [
        "id_ed25519"
        "clan-gitea"
      ];
      extraFlags = [ "--systemd" ];
    };

    sway = {
      enable = true;
      outputs = {
        DP-4 = {
          bg = "${../../modules/sway/blackhole.jpg} fill";
          subpixel = "none";
          scale = "2";
        };
      };
    };

    waybar.enable = true;
  };

  networking.hosts = {
    "127.0.0.1" = [
      "kubernetes"
    ];
  };

  programs.obs-studio.enable = true;
  programs.tmux.enable = true;
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake = "/home/collin/brew";
  };

  programs.kdeconnect.enable = true;

  facter.reportPath = ./facter.json;

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

  services.emacs = {
    enable = true;
    defaultEditor = true;
    startWithGraphical = true;
  };

  boot.loader.systemd-boot.configurationLimit = 30;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "America/New_York";
  programs.zsh.enable = true;

  networking = {
    hostName = "azathoth";
    hostId = "20556d4b";
    nameservers = [
      "1.1.1.1"
      "9.9.9.9"
    ];
  };

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

  programs.ssh.setXAuthLocation = true;

  users.users.root.openssh.authorizedKeys.keyFiles = [
    ../../secrets/keys/collinarnett.pub
  ];

  nix.settings = {
    trusted-users = [ "collin" ];
    netrc-file = "/etc/nix/netrc";
    extra-sandbox-paths = [
      "/etc/nix/netrc"
    ];
  };

  virtualisation.docker.enable = true;
  virtualisation.oci-containers.backend = "docker";

  documentation.dev.enable = true;

  hardware.graphics.enable = true;

  services.openssh = {
    enable = true;
    ports = [ 8787 ];
    settings.X11Forwarding = true;
    settings.PermitRootLogin = "yes";
    hostKeys = [
      {
        type = "ed25519";
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
      }
      {
        type = "rsa";
        bits = 4096;
        path = "/persist/etc/ssh/ssh_host_rsa_key";
      }
    ];
    settings.PasswordAuthentication = true;
  };

  # Home-manager user config
  home-manager.users.${config.brew.user} = {
    home.username = "collin";
    home.homeDirectory = "/home/collin";
    home.sessionVariables = {
      GH_TOKEN = "$(cat ${config.sops.secrets.gh_token.path})";
      GPG_TTY = "$(tty)";
    };

    home.packages = with pkgs; [
      alejandra
      anki-bin
      bash-language-server
      bibata-cursors
      chromium
      clang-tools
      claude-code
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

  system.stateVersion = "24.11";
}
