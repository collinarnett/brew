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
    ../../modules/home-manager/taskwarrior.nix
    ../../modules/home-manager/waybar/waybar.nix
    ../../modules/home-manager/wofi/wofi.nix
    ../../modules/home-manager/zathura/zathura.nix
    ../../modules/home-manager/zsh.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";
  home.sessionVariables = {
    GPG_TTY = "$(tty)";
    KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    GH_TOKEN = "$(cat ${nixosConfig.sops.secrets.gh_token.path})";
    XDG_SESSION_TYPE = "wayland";
    XDG_CURRENT_DESKTOP = "sway";
    BROWSER = "firefox";
  };

  home.packages = let
    whipper = pkgs.whipper.override {python3 = pkgs.python311;};
  in
    with pkgs;
      [
        adwaita-icon-theme
        alejandra
        anki-bin
        audacity
        awscli2
        chromium
        clang-tools
        crawl
        croc
        dconf
        dfu-programmer
        dracula-theme
        firefox
        freetube
        fzf
        google-cloud-sdk
        gotop
        grim
        heimdall-gui
        helvum
        hunspellDicts.en_US
        imv
        iommu-groups
        ipafont
        languagetool
        liberation_ttf
        libreoffice
        libsForQt5.kdenlive
        mpv
        neofetch
        nil
        nix-index
        nixfmt-classic
        nmap
        obs-studio
        ormolu
        pandoc
        parted
        pavucontrol
        pciutils
        pinta
        pulseaudio
        qmk
        qpwgraph
        ripgrep
        signal-desktop
        slurp
        statix
        texlive.combined.scheme-tetex
        tree
        unzip
        usbutils
        v4l-utils
        vhs
        wget
        wl-clipboard
        virt-manager
        xournalpp
        xplr
        zip
      ]
      ++ [whipper];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;
}
