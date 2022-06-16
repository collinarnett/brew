{ nixosConfig, config, pkgs, ... }:

{
  imports = [
    ../../modules/home-manager/gh.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/mpd.nix
    ../../modules/home-manager/ncmpcpp.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/swayidle.nix
    ../../modules/home-manager/taskwarrior.nix
    ../../modules/home-manager/vim/vim.nix
    ../../modules/home-manager/wofi/wofi.nix
    ../../modules/home-manager/zathura.nix
    ../../modules/wofi.nix
    ./modules/foot.nix
    ./modules/sway.nix
    ./modules/waybar/waybar.nix
    ./modules/zsh.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";

  home.packages = with pkgs; [
    cataclysm-dda
    black
    fira-code
    firefox
    git
    gotop
    grim
    helvum
    nixfmt
    nodejs
    noto-fonts-emoji
    pavucontrol
    pfetch
    pulseaudio
    python39Packages.isort
    rsync
    siji
    slurp
    statix
    swaylock
    vim-vint
    wl-clipboard
    yamlfix
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;

}
