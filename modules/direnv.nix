{ ... }:
{
  flake.modules.homeManager.direnv =
    { config, lib, ... }:
    let
      cfg = config.brew.direnv;
    in
    {
      options.brew.direnv.enable = lib.mkEnableOption "direnv";
      config = lib.mkIf cfg.enable {
        programs.direnv = {
          enable = true;
          enableZshIntegration = true;
          nix-direnv.enable = true;
        };
      };
    };
}
