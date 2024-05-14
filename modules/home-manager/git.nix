{
  programs.git = {
    enable = true;
    userEmail = "collin@arnett.it";
    userName = "Collin Arnett";
    difftastic.enable = true;
    extraConfig = {commit = {verbose = true;};};
    signing = {
      key = "A85650D42EB741D9";
      signByDefault = true;
    };
    lfs.enable = true;
  };
}
