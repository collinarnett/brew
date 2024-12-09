{
  nixosConfig,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/home-manager/beets.nix
    ../../modules/home-manager/direnv.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/gtk.nix
    ../../modules/home-manager/k9s/k9s.nix
    ../../modules/home-manager/keychain.nix
    ../../modules/home-manager/kitty.nix
    ../../modules/home-manager/mako.nix
    ../../modules/home-manager/ssh.nix
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

  home.packages = let
    whipper = pkgs.whipper.override {python3 = pkgs.python311;};
  in
    with pkgs; [
      alejandra
      chromium
      clang-tools
      crawl
      dconf
      freetube
      fzf
      gotop
      hunspellDicts.en_US
      iommu-groups
      languagetool
      neofetch
      nil
      pandoc
      pciutils
      pulseaudio
      ripgrep
      signal-desktop
      statix
      tree
      unzip
      usbutils
      wget
      whipper
      xplr
      zip
    ];

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
}
