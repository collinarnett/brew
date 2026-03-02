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
  brew.ollama.enable = true;

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

  services.openssh.enable = true;
  services.getty.autologinUser = "collin";
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  virtualisation.docker = {
    enable = true;
    package = pkgs.docker_25;
  };

  # ── Nix Settings ──────────────────────────────────────────────────

  nix.settings = {
    sandbox = true;
    trusted-users = [ "@wheel" ];
    substituters = [ "https://cache.nixos.org/" ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  nixpkgs.config.allowUnfree = true;

  # ── Packages ──────────────────────────────────────────────────────

  environment.systemPackages = with pkgs; [
    vim
    podman-compose
    git
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
      black
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
      wget
    ];

    home.stateVersion = "21.11";
    programs.home-manager.enable = true;
  };
}
