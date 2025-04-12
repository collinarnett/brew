{ ... }:
{
  programs.wofi = {
    enable = true;
    style = builtins.readFile ./style.css;
    settings = {
      show = "run";
    };
  };
}
