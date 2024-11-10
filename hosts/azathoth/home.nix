{
  nixosConfig,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/home-manager/beets.nix
    ../../modules/home-manager/direnv.nix
    ../../modules/home-manager/gh.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/gtk.nix
    ../../modules/home-manager/k9s/k9s.nix
    ../../modules/home-manager/keychain.nix
    ../../modules/home-manager/kitty.nix
    ../../modules/home-manager/mako.nix
    ../../modules/home-manager/mpd.nix
    ../../modules/home-manager/ncmpcpp.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/sway.nix
    ../../modules/home-manager/waybar/waybar.nix
    ../../modules/home-manager/wofi/wofi.nix
    ../../modules/home-manager/zathura/zathura.nix
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
    dracula-theme
    fzf
    gotop
    grim
    hunspellDicts.en_US
    iommu-groups
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
    ripgrep
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
