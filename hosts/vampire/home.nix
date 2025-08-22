{pkgs, ...}: {
  imports = [
    ../../modules/home-manager/btop.nix
    ../../modules/home-manager/direnv.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/zsh.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";

  home.packages = with pkgs; [
    alejandra
    black
    fira-code
    git
    nil
    nixfmt-classic
    nodejs
    noto-fonts-emoji
    statix
    tree
    unzip
    wget
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;
}
