{ nixosConfig, config, pkgs, ... }:

{
  imports = [
    ../../modules/home-manager/gh.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/gtk.nix
    ../../modules/home-manager/keychain.nix
    ../../modules/home-manager/kitty.nix
    ../../modules/home-manager/mpd.nix
    ../../modules/home-manager/ncmpcpp.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/sway.nix
    ../../modules/home-manager/taskwarrior.nix
    ../../modules/home-manager/vim.nix
    ../../modules/home-manager/waybar/waybar.nix
    ../../modules/home-manager/wofi/wofi.nix
    ../../modules/home-manager/zsh.nix
    ../../modules/wofi.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";
  home.sessionVariables = {
    GPG_TTY = "$(tty)";
    GH_TOKEN = "$(cat ${nixosConfig.sops.secrets.gh_token.path})";
  };

  home.packages = with pkgs; [
    anki
    dconf
    dracula-theme
    fira-code
    fira-code-symbols
    firefox
    grim
    helvum
    htop
    imv
    liberation_ttf
    lynx
    mpv
    neofetch
    nix-index
    nixfmt
    nmap
    nodejs
    pciutils
    pfetch
    pulseaudio
    rclone
    signal-desktop
    siji
    slurp
    statix
    tree
    ttyper
    virt-manager
    wget
    whipper
    wl-clipboard
    youtube-dl
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;

}

