{pkgs, ...}: {
  imports = [
    ../../modules/home-manager/gh.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/mpd.nix
    ../../modules/home-manager/ncmpcpp.nix
    ../../modules/home-manager/neovim/neovim.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/swayidle.nix
    ../../modules/home-manager/swaylock.nix
    ../../modules/home-manager/taskwarrior.nix
    ../../modules/home-manager/wofi/wofi.nix
    ../../modules/home-manager/zathura.nix
    ./modules/foot.nix
    ./modules/sway.nix
    ./modules/waybar/waybar.nix
    ./modules/zsh.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";

  home.packages = with pkgs; [
    fira-code
    firefox
    git
    gotop
    grim
    helvum
    nerdfonts
    pavucontrol
    pfetch
    pulseaudio
    noto-fonts-emoji
    siji
    slurp
    swaylock
    wl-clipboard
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;
}
