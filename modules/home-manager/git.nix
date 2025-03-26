{
  programs.git = {
    enable = true;
    userEmail = "collin@arnett.it";
    userName = "Collin Arnett";
    difftastic.enable = false;
    extraConfig = {
      rebase = {
        autostash = true;
      };
      commit = {verbose = true;};
      core = {
        fsmonitor = true;
        untrackedcache = true;
      };
      fetch = {
        writeCommitGraph = true;
      };
    };
    signing = {
      key = "A85650D42EB741D9";
      signByDefault = true;
    };
    lfs.enable = true;
  };
}
