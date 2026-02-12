{
  nixosConfig,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../../modules/home-manager/autojump.nix
    ../../modules/home-manager/bat.nix
    ../../modules/home-manager/beets.nix
    ../../modules/home-manager/btop.nix
    ../../modules/home-manager/direnv.nix
    ../../modules/home-manager/fzf.nix
    ../../modules/home-manager/gh.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/gtk.nix
    ../../modules/home-manager/k9s/k9s.nix
    ../../modules/home-manager/keychain.nix
    ../../modules/home-manager/kitty.nix
    ../../modules/home-manager/mako.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/sway.nix
    ../../modules/home-manager/waybar/waybar.nix
    ../../modules/home-manager/wofi/wofi.nix
    ../../modules/home-manager/zathura/zathura.nix
    ../../modules/home-manager/zoxide.nix
    ../../modules/home-manager/zsh.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";
  home.sessionVariables = {
    GH_TOKEN = "$(cat ${nixosConfig.sops.secrets.gh_token.path})";
    GPG_TTY = "$(tty)";
  };

  home.packages =
    with pkgs;
    [
      alejandra
      anki-bin
      bash-language-server
      bibata-cursors
      chromium
      clang-tools
      claude-code
      cloc
      crawl
      dconf
      drawio
      electron_38
      fastfetch
      fd
      freetube
      graphviz
      hledger
      httpie
      hunspellDicts.en_US
      imv
      iommu-groups
      jq
      languagetool
      leiningen
      libreoffice
      nil
      nix-output-monitor
      nix-tree
      nixfmt
      nixpkgs-review
      pandoc
      pciutils
      pinta
      pulseaudio
      pyright
      ripgrep
      ruff
      signal-desktop
      statix
      tealdeer
      texliveFull
      timg
      tree
      unzip
      usbutils
      waypipe
      wget
      whipper
      wl-clipboard
      xauth
      xplr
      zip
    ];

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
}
