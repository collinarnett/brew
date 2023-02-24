{
  nixosConfig,
  config,
  pkgs,
  ...
}: {
  imports = [
    # ./modules/qutebrowser.nix
    ../../modules/home-manager/gpg-agent.nix
    ../../modules/home-manager/gpg.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/vim/vim.nix
    ../../modules/home-manager/wofi/wofi.nix
    ../../modules/home-manager/zathura.nix
    ../../modules/wofi.nix
    ./modules/zsh.nix
    ./modules/foot.nix
    ./modules/sway.nix
    ./modules/waybar/waybar.nix
  ];

  home.username = "collin";
  home.homeDirectory = "/home/collin";
  home.sessionVariables = {GPG_TTY = "$(tty)";};

  home.packages = with pkgs; [
    fira-code
    git
    gotop
    grim
    lynx
    nixfmt
    nodejs
    pfetch
    siji
    slurp
    statix
    wl-clipboard
  ];

  home.stateVersion = "21.11";
  programs.home-manager.enable = true;
}
