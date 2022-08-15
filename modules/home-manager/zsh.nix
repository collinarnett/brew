{ pkgs, ...}:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    enableSyntaxHighlighting = true;
    initExtra = ''
      source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
    '';
    oh-my-zsh = {
      enable = true;
      plugins = [ "colored-man-pages" ];
    };
    shellAliases = {
      update = "sudo nixos-rebuild switch --flake ~/brew";
      ssh = "kitty +kitten ssh";
#      k = "sudo k3s kubectl";
      vimwiki = "vim -c VimwikiIndex";
      pg =
        "docker run --rm -v /home/collin/projects/PersonalGamification/test:/var/lib/pg collinarnett/personalgamification:g51499qvhx2x6fv3x4gxn233r01bbja5";
    };
  };
}
