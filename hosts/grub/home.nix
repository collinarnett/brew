{ nixosConfig, config, pkgs, ... }:

{
  imports = [
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/vim.nix
    ../../modules/home-manager/zsh.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";
  home.sessionVariables = {
    GPG_TTY = "$(tty)";
  };

  home.packages = with pkgs; [
    htop
    pciutils
    wget
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;

}
