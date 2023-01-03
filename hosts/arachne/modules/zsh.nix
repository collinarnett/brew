{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    enableSyntaxHighlighting = true;
    oh-my-zsh = {
      enable = true;
      plugins = ["colored-man-pages"];
    };
    shellAliases = {
      update = "sudo nixos-rebuild switch --flake ~/brew";
      vimwiki = "vim -c VimwikiIndex";
    };
  };
}
