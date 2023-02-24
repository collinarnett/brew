{
  nixosConfig,
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/home-manager/direnv.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/vim/vim.nix
    ../../modules/home-manager/zsh.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";

  home.packages = with pkgs; [
    black
    alejandra
    fira-code
    git
    gotop
    nixfmt
    nodejs
    noto-fonts-emoji
    python39Packages.isort
    statix
    unzip
    vim-vint
    wget
    yamlfix
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;
}