{
  config,
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
  brew.ollama.enable = true;
  brew.prometheus.enable = true;
  brew.grafana.enable = true;
  brew.sillytavern.enable = true;

  brew.whisperlivekit = {
    enable = true;
    package = pkgs.whisperlivekit-cuda;
    model = "base";
    port = 8010;
    openFirewall = true;
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
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
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
  programs.tmux.enable = true;

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
      nixfmt-classic
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

    home.stateVersion = "21.11";
    programs.home-manager.enable = true;
  };
}
