{ nixosConfig, config, pkgs, ... }:

{
  imports = [
    ../../modules/home-manager/gh.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/vim.nix
    ../../modules/home-manager/wofi/wofi.nix
    ../../modules/home-manager/zathura.nix
    ../../modules/home-manager/zsh.nix
    ../../modules/wofi.nix
    ./modules/foot.nix
    ./modules/sway.nix
    ./modules/waybar/waybar.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";
  home.sessionVariables = {
    GPG_TTY = "$(tty)";
    WLR_NO_HARDWARE_CURSORS = 1;
    GH_TOKEN = "$(cat ${nixosConfig.sops.secrets.gh_token.path})";
  };

  home.packages = with pkgs; [
    cataclysm-dda
    fira-code
    firefox
    git
    gotop
    grim
    helvum
    nixfmt
    nodejs
    pfetch
    siji
    slurp
    statix
    wl-clipboard
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;

}
