{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    enableSyntaxHighlighting = true;
    shellAliases = { update = "sudo nixos-rebuild switch --flake ~/brew"; };
  };
}
