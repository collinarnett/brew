{pkgs, ...}: {
  imports = [
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/zathura.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/Users/collin/";

  home.packages = with pkgs; [
    fira-code
    firefox
    git
    nerdfonts
    pfetch
    noto-fonts-emoji
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;
}
