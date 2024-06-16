{pkgs, ...}: {
  imports = [
    ../../modules/home-manager/direnv.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/gtk.nix
    ../../modules/home-manager/ncmpcpp.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/zsh.nix
    ./modules/sway.nix
    ./modules/waybar/waybar.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";

  home.packages = with pkgs; [
    croc
    fira-code
    git
    neofetch
    nerdfonts
    ripgrep
    slurp
    tree
    unzip
  ];

  home.stateVersion = "23.11";
  programs.home-manager.enable = true;
}
