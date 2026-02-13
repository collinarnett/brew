{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.brew.greetd;
in
{
  options.brew.greetd.enable = lib.mkEnableOption "greetd";
  config = lib.mkIf cfg.enable {
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd sway";
          user = "collin";
        };
      };
    };
  };
}
