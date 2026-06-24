{ ... }:
{
  flake.modules.homeManager.zsh =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.zsh;
    in
    {
      options.brew.zsh.enable = lib.mkEnableOption "zsh";
      config = lib.mkIf cfg.enable {
        programs.zsh = {
          enable = true;
          enableCompletion = true;
          autosuggestion.enable = true;
          syntaxHighlighting.enable = true;
          initContent = ''
            source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh

            # zsh-vi-mode lazy-loads and rebinds ^R to its own history search,
            # clobbering fzf's widget. Restore fzf's binding after zvm finishes.
            zvm_after_init() {
              zvm_bindkey viins '^R' fzf-history-widget
              zvm_bindkey vicmd '^R' fzf-history-widget
            }
          '';
          oh-my-zsh = {
            enable = true;
            plugins = [ "colored-man-pages" ];
          };
          shellAliases = {
            update = "${pkgs.nh}/bin/nh os switch /home/collin/brew";
            cat = "${pkgs.bat}/bin/bat";
          };
          history.path = "$HOME/.local/share/zsh/.zsh_history";
        };
      };
    };
}
