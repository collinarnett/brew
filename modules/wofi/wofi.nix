{ ... }:
{
  flake.modules.homeManager.wofi =
    { config, lib, ... }:
    let
      cfg = config.brew.wofi;
    in
    {
      options.brew.wofi.enable = lib.mkEnableOption "wofi";
      config = lib.mkIf cfg.enable {
        programs.wofi = {
          enable = true;
          style = builtins.readFile ./style.css;
          settings = {
            show = "run";
          };
        };
      };
    };
}
