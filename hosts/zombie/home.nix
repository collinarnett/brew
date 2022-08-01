{ nixosConfig, config, pkgs, ... }:

{
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
    ../../modules/home-manager/mpd.nix
    ../../modules/home-manager/ncmpcpp.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/sway.nix
    ../../modules/home-manager/taskwarrior.nix
    ../../modules/home-manager/vim/vim.nix
    ../../modules/home-manager/waybar/waybar.nix
    ../../modules/home-manager/wofi/wofi.nix
    ../../modules/home-manager/zathura.nix
    ../../modules/home-manager/zsh.nix
    ../../modules/wofi.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";
  home.sessionVariables = {
    GPG_TTY = "$(tty)";
    KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    GH_TOKEN = "$(cat ${nixosConfig.sops.secrets.gh_token.path})";
#    AWS_CONFIG_FILE = nixosConfig.sops.secrets.awscli2-config.path;
#    AWS_SHARED_CREDENTIALS_FILE =
#      nixosConfig.sops.secrets.awscli2-credentials.path;
    XDG_SESSION_TYPE = "wayland";
    XDG_CURRENT_DESKTOP = "sway";
    BROWSER = "firefox";
  };

  home.packages = with pkgs; [
    anki-bin
    astyle
    awscli2
    black
    dconf
    dracula-theme
    fira-code
    fira-code-symbols
    firefox
    google-cloud-sdk
    gotop
    grim
    helvum
    imv
    ipafont
    kubernetes-helm
    k9s
    lens
    liberation_ttf
    lynx
    mpv
    neofetch
    nix-index
    nixfmt
    nmap
    nodePackages.prettier
    nodejs
    noto-fonts-emoji
    nyxt
    obs-studio
    ormolu
    pandoc
    parted
    pciutils
    pfetch
    pulseaudio
    python39Packages.isort
    rclone
    signal-desktop
    siji
    slurp
    statix
    super-slicer
    timewarrior
    tree
    usbutils
    vial
    virt-manager
    wget
    whipper
    wl-clipboard
    xdg-desktop-portal
    xdg-desktop-portal-wlr
    yamlfix
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;

}

