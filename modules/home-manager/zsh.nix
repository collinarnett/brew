{pkgs, ...}: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    initExtra = ''
      source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
    '';
    oh-my-zsh = {
      enable = true;
      plugins = ["colored-man-pages"];
    };
    shellAliases = {
      update = "sudo nixos-rebuild switch --flake ~/brew";
      ssh = "kitty +kitten ssh";
      vimwiki = "vim -c VimwikiIndex";
    };
  };
}
