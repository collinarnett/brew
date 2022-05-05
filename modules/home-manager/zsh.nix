{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    enableSyntaxHighlighting = true;
    oh-my-zsh = {
      enable = true;
      plugins = [ "colored-man-pages" ];
    };
    shellAliases = {
      update = "sudo nixos-rebuild switch --flake ~/brew";
      ssh = "kitty +kitten ssh";
      kubectl = "sudo k3s kubectl";
      pg =
        "docker run --rm -v /home/collin/projects/PersonalGamification/test:/var/lib/pg collinarnett/personalgamification:g51499qvhx2x6fv3x4gxn233r01bbja5";
    };
  };
}
