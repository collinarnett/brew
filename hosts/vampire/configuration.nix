{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
  ];

  # ── Brew Module Configuration ─────────────────────────────────────

  brew.common.enable = true;
  brew.claude-code.enable = true;
  brew.ollama = {
    enable = true;
    models."gpt-oss-heretic-ara-v4:20b" = pkgs.gpt-oss-20b-heretic-ara-v4;
  };
  brew.prometheus.enable = true;
  brew.grafana.enable = true;
  brew.sillytavern.enable = true;
  brew.steam.enable = true;

  brew.whisperlivekit = {
    enable = true;
    package = pkgs.whisperlivekit-server-cuda;
    model = "base";
    port = 8010;
    openFirewall = true;
    transcriptOutput.enable = true;
  };

  # Enable SysRq for emergency recovery
  boot.kernel.sysctl."kernel.sysrq" = 1;

  # ── Boot ──────────────────────────────────────────────────────────

  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
    useOSProber = true;
  };

  # ── Networking ────────────────────────────────────────────────────

  networking.hostName = "vampire";
  networking.networkmanager.enable = true;

  # ── Hardware ──────────────────────────────────────────────────────

  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = true;
  hardware.opengl.enable = true;
  hardware.nvidia-container-toolkit.enable = true;

  # ── Users ─────────────────────────────────────────────────────────

  users.users.collin = {
    isNormalUser = true;
    description = "Collin";
    # Declared so services.moonshine can derive the uid of the user
    # manager it runs under.
    uid = 1000;
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
      # Streamed games read the virtual gamepads moonshine creates. The
      # group grants that without depending on an active seat session.
      "input"
    ];
  };

  programs.zsh.enable = true;

  # ── Services ──────────────────────────────────────────────────────

  services.emacs = {
    enable = true;
    defaultEditor = true;
    startWithGraphical = true;
  };

  services.ollama = {
    package = pkgs.ollama-cuda;
    openFirewall = true;
    host = "0.0.0.0";
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = "65536";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
    };
    loadModels = [ "gpt-oss:20b" ];
  };

  services.moonshine = {
    enable = true;
    user = "collin";
    # vampire sits behind libvirt NAT on azathoth, so clients reach it over
    # yggdrasil, whose interface already drops traffic from non-clan peers.
    openFirewall = true;
    settings = {
      name = "vampire";
      # Yggdrasil is IPv6-only and moonshine binds IPv4-only by default.
      address = "::";
      application = [
        {
          title = "Steam";
          command = [
            (lib.getExe config.programs.steam.package)
            "steam://open/bigpicture"
          ];
        }
      ];
      application_scanner = [
        {
          type = "steam";
          library = "$HOME/.local/share/Steam";
          command = [
            (lib.getExe config.programs.steam.package)
            "-bigpicture"
            "steam://rungameid/{game_id}"
          ];
        }
      ];
    };
  };

  services.openssh = {
    enable = true;
    forwardX11 = true;
  };

  services.getty.autologinUser = "collin";
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  virtualisation.docker = {
    enable = true;
    package = pkgs.docker_25;
  };

  # ── Programs ──────────────────────────────────────────────────────

  programs.ssh.setXAuthLocation = true;

  # ── Nix Settings ──────────────────────────────────────────────────

  nix.settings = {
    sandbox = true;
    trusted-users = [ "@wheel" ];
  };

  nixpkgs.config.allowUnfree = true;

  # ── Packages ──────────────────────────────────────────────────────

  environment.systemPackages = with pkgs; [
    vim
    podman-compose
    git
    nvtopPackages.nvidia
  ];

  # ── System ────────────────────────────────────────────────────────

  time.timeZone = "America/New_York";
  system.stateVersion = "22.05";

  # ── Home Manager ──────────────────────────────────────────────────

  home-manager.users.${config.brew.user} = {
    home.username = "collin";
    home.homeDirectory = "/home/collin";

    home.packages = with pkgs; [
      alejandra
      bat
      black
      fd
      fira-code
      git
      hunspellDicts.en_US
      nixd
      nixfmt
      nodejs
      noto-fonts-color-emoji
      ripgrep
      statix
      tree
      unzip
      waypipe
      wget
      xauth
    ];

    programs.btop.package = pkgs.btop-cuda;

    brew.radicle.enable = true;

    home.stateVersion = "21.11";
    programs.home-manager.enable = true;
  };
}
