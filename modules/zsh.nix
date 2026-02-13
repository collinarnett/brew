{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.brew.zsh;
  user = config.brew.user;
in
{
  options.brew.zsh.enable = lib.mkEnableOption "zsh" // {
    default = true;
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;
        initContent = ''
          source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
        '';
        oh-my-zsh = {
          enable = true;
          plugins = [ "colored-man-pages" ];
        };
        shellAliases = {
          update = "${pkgs.nh}/bin/nh os switch /home/collin/brew";
          ssh = "kitty +kitten ssh";
          cat = "${pkgs.bat}/bin/bat";
        };
        history.path = "$HOME/.local/share/zsh/.zsh_history";
      };
    };
  };
}
