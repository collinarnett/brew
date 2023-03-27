{pkgs, ...}: {
  programs.foot = {
    enable = true;
    settings = {
      main = {font = "Fira Code:size11";};
      colors = {
        ## Normal/regular colors (color palette 0-7)
        regular0 = "21222c"; # black
        regular1 = "ff5555"; # red
        regular2 = "50fa7b"; # green
        regular3 = "f1fa8c"; # yellow
        regular4 = "bd93f9"; # blue
        regular5 = "ff79c6"; # magenta
        regular6 = "8be9fd"; # cyan
        regular7 = "f8f8f2"; # white

        ## Brigh = "2t colors (color palette 8-15)
        bright0 = "6272a4"; # bright black
        bright1 = "ff6e6e"; # bright red
        bright2 = "69ff94"; # bright green
        bright3 = "ffffa5"; # bright yellow
        bright4 = "d6acff"; # bright blue
        bright5 = "ff92df"; # bright magenta
        bright6 = "a4ffff"; # bright cyan
        bright7 = "ffffff"; # bright white
        selection-foreground = "ffffff";
        selection-background = "44475a";
        background = "282a36";
	foreground="f8f8f2";
        alpha = "0.8";
        urls = "8be9fd";
      };
    };
  };
}
