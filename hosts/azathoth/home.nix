{
  nixosConfig,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/home-manager/direnv.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/keychain.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/zsh.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";
  home.sessionVariables = {
    GPG_TTY = "$(tty)";
  };

  home.packages = with pkgs; [
    alejandra
    awscli2
    clang-tools
    crawl
    dconf
    ripgrep
    dracula-theme
    fzf
    gotop
    grim
    hunspellDicts.en_US
    ipafont
    languagetool
    liberation_ttf
    neofetch
    nil
    ormolu
    pandoc
    parted
    pciutils
    pinta
    pulseaudio
    slurp
    statix
    tree
    unzip
    usbutils
    wget
    xplr
    zip
  ];

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
}
