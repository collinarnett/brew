{pkgs, ...}: {
  imports = [
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/zathura.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/Users/collin/";

  home.packages = with pkgs; [
    discord
    fira-code
    nur.repos.toonn.apps.firefox
    git
    nerdfonts
    pfetch
    noto-fonts-emoji
    teams
    slack
    # apps I would like but are not availible for aarch64-darwin
    # firefox
    # signal-desktop
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;
}
