{ ... }:
{
  flake.modules.homeManager.gh =
    { config, lib, ... }:
    let
      cfg = config.brew.gh;
    in
    {
      options.brew.gh.enable = lib.mkEnableOption "gh";
      config = lib.mkIf cfg.enable {
        programs.gh = {
          enable = true;
        };
      };
    };
}
