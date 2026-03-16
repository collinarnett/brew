{ inputs, ... }:
{
  flake.modules.nixos.prometheus-dcgm =
    { pkgs, ... }:
    let
      pkgs-prometheus = import inputs.nixpkgs-prometheus {
        inherit (pkgs) system;
        config.allowUnfree = true;
      };
    in
    {
      disabledModules = [
        "services/monitoring/prometheus/exporters.nix"
      ];
      imports = [
        "${inputs.nixpkgs-prometheus}/nixos/modules/services/monitoring/prometheus/exporters.nix"
      ];
      nixpkgs.overlays = [
        (final: prev: {
          prometheus-dcgm-exporter = pkgs-prometheus.prometheus-dcgm-exporter;
        })
      ];
    };
}
