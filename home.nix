{ config, pkgs, ... }:

{
  imports = [
    ./modules/home-manager/git.nix
    ./modules/home-manager/gpg-agent.nix
    ./modules/home-manager/gpg.nix
    ./modules/home-manager/gtk.nix
    ./modules/home-manager/keychain.nix
    ./modules/home-manager/kitty.nix
    ./modules/home-manager/mpd.nix
    ./modules/home-manager/ncmpcpp.nix
    ./modules/home-manager/starship.nix
    ./modules/home-manager/sway.nix
    ./modules/home-manager/taskwarrior.nix
    ./modules/home-manager/vim.nix
    ./modules/home-manager/waybar/waybar.nix
    ./modules/home-manager/wofi/wofi.nix
    ./modules/home-manager/zsh.nix
    ./modules/wofi.nix
    # WIP
    # ./modules/home-manager/awscli2.nix
    # ./modules/awscli2.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";
  home.sessionVariables = {
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
    GPG_TTY = "$(tty)";
  };

  home.packages = with pkgs; [
    anki
    dconf
    dracula-theme
    fira-code
    fira-code-symbols
    firefox
    grim
    htop
    imv
    mpv
    neofetch
    nixfmt
    pciutils
    pfetch
    rclone
    siji
    slurp
    statix
    tree
    ttyper
    wget
    whipper
    wl-clipboard
    youtube-dl
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;

}

