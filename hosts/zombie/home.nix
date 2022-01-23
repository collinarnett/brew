{ nixosConfig, config, pkgs, ... }:

{
  imports = [
    ../../modules/home-manager/beets.nix
    ../../modules/home-manager/gh.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/gtk.nix
    ../../modules/home-manager/keychain.nix
    ../../modules/home-manager/kitty.nix
    ../../modules/home-manager/mpd.nix
    ../../modules/home-manager/ncmpcpp.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/sway.nix
    ../../modules/home-manager/taskwarrior.nix
    ../../modules/home-manager/vim.nix
    ../../modules/home-manager/waybar/waybar.nix
    ../../modules/home-manager/wofi/wofi.nix
    ../../modules/home-manager/zsh.nix
    ../../modules/wofi.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";
  home.sessionVariables = {
    GPG_TTY = "$(tty)";
    GH_TOKEN = "$(cat ${nixosConfig.sops.secrets.gh_token.path})";
    AWS_CONFIG_FILE = nixosConfig.sops.secrets.awscli2-config.path;
    AWS_SHARED_CREDENTIALS_FILE = nixosConfig.sops.secrets.awscli2-credentials.path;
  };

  home.packages = with pkgs; [
    anki
    awscli2
    dconf
    dracula-theme
    fira-code
    fira-code-symbols
    firefox
    gotop
    grim
    helvum
    imv
    liberation_ttf
    lynx
    mpv
    neofetch
    nix-index
    nixfmt
    nmap
    nodejs
    pandoc
    pciutils
    pfetch
    pulseaudio
    rclone
    signal-desktop
    siji
    slurp
    statix
    tree
    unzip
    virt-manager
    wget
    whipper
    wl-clipboard
    youtube-dl
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;

}

