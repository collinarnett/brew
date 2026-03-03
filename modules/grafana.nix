{ ... }:
{
  flake.nixosModules.grafana =
    { config, lib, ... }:
    let
      cfg = config.brew.grafana;
    in
    {
      options.brew.grafana.enable = lib.mkEnableOption "grafana";
      config = lib.mkIf cfg.enable {
        services.grafana = {
          enable = true;
          settings.security.secret_key = "SW2YcwTIb9zpOOhoPsMm";
        };
      };
    };
}
