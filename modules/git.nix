{ ... }:
{
  flake.modules.homeManager.git =
    { config, lib, ... }:
    let
      cfg = config.brew.git;
    in
    {
      options.brew.git.enable = lib.mkEnableOption "git";
      config = lib.mkIf cfg.enable {
        programs.difftastic.enable = false;
        programs.git = {
          enable = true;
          settings = {
            user = {
              email = "collin@arnett.it";
              name = "Collin Arnett";
            };
            rebase = {
              autostash = true;
            };
            commit = {
              verbose = true;
            };
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
      };
    };
}
