{ ... }:
{
  flake.modules.homeManager.btop =
    { config, lib, ... }:
    let
      cfg = config.brew.btop;
    in
    {
      options.brew.btop.enable = lib.mkEnableOption "btop";
      config = lib.mkIf cfg.enable {
        programs.btop = {
          enable = true;
          settings = {
            color_theme = "dracula";
          };
        };
      };
    };
}
