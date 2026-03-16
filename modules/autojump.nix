{ ... }:
{
  flake.modules.homeManager.autojump =
    { config, lib, ... }:
    let
      cfg = config.brew.autojump;
    in
    {
      options.brew.autojump.enable = lib.mkEnableOption "autojump";
      config = lib.mkIf cfg.enable {
        programs.autojump = {
          enable = true;
          enableZshIntegration = true;
        };
      };
    };
}
