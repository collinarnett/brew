{ nixosConfig, config, pkgs, ... }:

{
  imports = [
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/kitty.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/vim.nix
    ../../modules/home-manager/wofi/wofi.nix
    ../../modules/home-manager/zsh.nix
    ../../modules/wofi.nix
    ./modules/sway.nix
    ./modules/foot.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";
  home.sessionVariables = {
    GPG_TTY = "$(tty)";
  };

  home.packages = with pkgs; [
    git
    grim
    glxinfo
    nodejs
    slurp
    fira-code
    wl-clipboard
    pfetch
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;

}
