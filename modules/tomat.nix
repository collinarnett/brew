{ ... }:
let
  tomatOptions =
    { lib, ... }:
    {
      options.brew.tomat = {
        enable = lib.mkEnableOption "tomat pomodoro timer";
      };
    };
in
{
  flake.modules.nixos.tomat =
    { config, lib, ... }:
    let
      cfg = config.brew.tomat;
    in
    {
      imports = [ tomatOptions ];
      config = lib.mkIf cfg.enable {
        home-manager.sharedModules = [
          { brew.tomat.enable = true; }
        ];
      };
    };

  flake.modules.homeManager.tomat =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.brew.tomat;
    in
    {
      imports = [ tomatOptions ];
      config = lib.mkIf cfg.enable {
        services.tomat = {
          enable = true;
          settings = {
            timer = {
              work = 60.0;
              break = 15.0;
              long_break = 30.0;
              sessions = 2;
            };
            display.icons = {
              work = "💀";
            };
          };
        };
      };
    };
}
