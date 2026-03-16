{ ... }:
{
  flake.modules.homeManager.bat =
    { config, lib, ... }:
    let
      cfg = config.brew.bat;
    in
    {
      options.brew.bat.enable = lib.mkEnableOption "bat";
      config = lib.mkIf cfg.enable {
        programs.bat = {
          enable = true;
          config = {
            theme = "Dracula";
          };
        };
      };
    };
}
