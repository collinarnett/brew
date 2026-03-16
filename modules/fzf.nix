{ ... }:
{
  flake.modules.homeManager.fzf =
    { config, lib, ... }:
    let
      cfg = config.brew.fzf;
    in
    {
      options.brew.fzf.enable = lib.mkEnableOption "fzf";
      config = lib.mkIf cfg.enable {
        programs.fzf = {
          enable = true;
          enableZshIntegration = true;
        };
      };
    };
}
