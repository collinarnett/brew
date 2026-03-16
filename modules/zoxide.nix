{ ... }:
{
  flake.modules.homeManager.zoxide =
    { config, lib, ... }:
    let
      cfg = config.brew.zoxide;
    in
    {
      options.brew.zoxide.enable = lib.mkEnableOption "zoxide";
      config = lib.mkIf cfg.enable {
        programs.zoxide = {
          enable = true;
          enableZshIntegration = true;
        };
      };
    };
}
