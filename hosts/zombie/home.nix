{
  nixosConfig,
  pkgs,
  ...
}: let
  customNixpkgs = import (pkgs.fetchFromGitHub {
    owner = "emilazy";
    repo = "nixpkgs";
    rev = "cdrdao-fixes";
    sha256 = "sha256-1G1BA72mVpwo6r5lT3D1OBw/+7ujOiN0CoVp2AztgfU=";
  }) {system = pkgs.system;};

  whipperCustom = customNixpkgs.whipper;
  emacs = (import ../../modules/emacs/emacs.nix) pkgs;
in {
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
    ../../modules/home-manager/mako/mako.nix
    ../../modules/home-manager/mpd.nix
    ../../modules/home-manager/ncmpcpp.nix
    ../../modules/home-manager/neovim/neovim.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/sway.nix
    ../../modules/home-manager/taskwarrior.nix
    ../../modules/home-manager/waybar/waybar.nix
    ../../modules/home-manager/wofi/wofi.nix
    ../../modules/home-manager/zathura.nix
    ../../modules/home-manager/zsh.nix
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
    OPENAI_API_KEY = "$(cat ${nixosConfig.sops.secrets.openai_api_key.path})";
    XDG_SESSION_TYPE = "wayland";
    XDG_CURRENT_DESKTOP = "sway";
    BROWSER = "firefox";
  };

  home.packages = with pkgs;
    [
      alejandra
      anki-bin
      asciiquarium
      audacity
      awscli2
      bear
      clang-tools
      crawl
      croc
      dconf
      deluge-gtk
      dfu-programmer
      dracula-theme
      emacs
      fira-code
      fira-code-symbols
      firefox
      fluffychat
      fzf
      google-cloud-sdk
      gotop
      grim
      heimdall-gui
      helvum
      hunspellDicts.en_US
      imv
      ipafont
      k9s
      keybase-gui
      kubectl
      kubernetes-helm
      languagetool
      liberation_ttf
      libsForQt5.kdenlive
      luaformatter
      lynx
      mpv
      neofetch
      nerdfonts
      nil
      nix-index
      nixfmt
      nmap
      nodePackages.prettier
      nodejs
      noto-fonts-emoji
      nyxt
      obs-studio
      openconnect
      ormolu
      pandoc
      parted
      pavucontrol
      pciutils
      pfetch
      pulseaudio
      qmk
      qpwgraph
      rclone
      rtorrent
      signal-desktop
      siji
      slurp
      statix
      super-slicer
      timewarrior
      tree
      unzip
      usbutils
      v4l-utils
      vhs
      virt-manager
      wget
      wl-clipboard
      xdg-desktop-portal
      xdg-desktop-portal-wlr
      xplr
      zip
    ]
    ++ [whipperCustom];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;
}
