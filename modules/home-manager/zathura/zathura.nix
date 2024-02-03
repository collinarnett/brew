{
  programs.zathura = {
    enable = true;
    options = {
      selection-clipboard = "clipboard";
    };
    extraConfig = builtins.readFile ./zathurarc;
  };
}
