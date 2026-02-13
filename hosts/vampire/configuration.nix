{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
  ];

  brew.ollama.enable = true;

  services.ollama.package = pkgs.ollama-cuda;
  services.ollama.openFirewall = true;
  services.ollama.host = "0.0.0.0";

  nix.settings.sandbox = true;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  virtualisation.docker.enable = true;
  virtualisation.docker.package = pkgs.docker_25;
  hardware.nvidia-container-toolkit.enable = true;

  services.emacs = {
    enable = true;
    defaultEditor = true;
    startWithGraphical = true;
  };

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.useOSProber = true;

  networking.hostName = "vampire";
  programs.zsh.enable = true;
  networking.networkmanager.enable = true;
  time.timeZone = "America/New_York";

  services.xserver.xkb.layout = "us";
  services.xserver.xkb.variant = "";

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

  services.getty.autologinUser = "collin";

  nixpkgs.config.allowUnfree = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = true;
  hardware.opengl.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    podman-compose
    git
  ];

  nix.settings.trusted-users = [ "@wheel" ];
  nix.settings.substituters = [ "https://cache.nixos.org/" ];
  nix.settings.trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
  ];

  services.openssh.enable = true;

  # Home-manager user config
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

  system.stateVersion = "22.05";
}
