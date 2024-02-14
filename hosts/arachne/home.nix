{pkgs, ...}: let
  ocean = pkgs.writeShellScriptBin "ocean" ''
    ${pkgs.sox}/bin/play -n synth brownnoise synth pinknoise mix synth sine amod 0.1 10
  '';
in {
  imports = [
    ../../modules/home-manager/direnv.nix
    ../../modules/home-manager/gh.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/gtk.nix
    ../../modules/home-manager/kitty.nix
    ../../modules/home-manager/mako.nix
    ../../modules/home-manager/mpd.nix
    ../../modules/home-manager/ncmpcpp.nix
    ../../modules/home-manager/neovim/neovim.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/swayidle.nix
    ../../modules/home-manager/swaylock.nix
    ../../modules/home-manager/wofi/wofi.nix
    ../../modules/home-manager/zathura.nix
    ../../modules/home-manager/zsh.nix
    ./modules/sway.nix
    ./modules/waybar/waybar.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";

  home.packages = with pkgs; [
    anki-bin
    fira-code
    firefox
    git
    gotop
    grim
    croc
    helvum
    imv
    mpv
    neofetch
    nerdfonts
    noto-fonts-emoji
    ocean
    openconnect
    pandoc
    pavucontrol
    poppler_utils
    pulseaudio
    ripgrep
    signal-desktop
    siji
    slurp
    thunderbird
    tree
    unzip
    wl-clipboard
    xournalpp
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;
}
