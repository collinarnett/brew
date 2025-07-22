{ pkgs, ... }:
let
  ocean = pkgs.writeShellScriptBin "ocean" ''
    ${pkgs.sox}/bin/play -n synth brownnoise synth pinknoise mix synth sine amod 0.1 10
  '';
in
{
  imports = [
    ../../modules/home-manager/bat.nix
    ../../modules/home-manager/btop.nix
    ../../modules/home-manager/direnv.nix
    ../../modules/home-manager/gh.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/gtk.nix
    ../../modules/home-manager/kitty.nix
    ../../modules/home-manager/mako.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/swayidle.nix
    ../../modules/home-manager/swaylock.nix
    ../../modules/home-manager/wofi/wofi.nix
    ../../modules/home-manager/zathura/zathura.nix
    ../../modules/home-manager/zsh.nix
    ./modules/keychain.nix
    ./modules/sway.nix
    ./modules/waybar/waybar.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";
  home.sessionVariables = {
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    GPG_TTY = "$(tty)";
  };

  home.packages = with pkgs; [
    anki-bin
    bluetui
    claude-code
    chromium
    croc
    drawio
    emacs-all-the-icons-fonts
    fira-code
    fira-code
    fira-code-symbols
    forge-mtg
    git
    gotop
    grim
    helvum
    imv
    libreoffice
    neofetch
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
