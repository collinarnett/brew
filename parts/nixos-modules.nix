{ inputs, ... }:
{
  flake.nixosModules = {
    prometheus-dcgm =
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
    nix-settings =
      { pkgs, ... }:
      {
        nixpkgs.overlays = [
          inputs.emacs-overlay.overlay
          (import ../overlays inputs)
          (import ../pkgs/all-packages.nix)
        ]
        ++ (builtins.attrValues (inputs.newt.overlays or { }));
        nixpkgs.config.allowUnfree = true;
        nix = {
          package = pkgs.nixVersions.latest;
          registry.pkgs.flake = inputs.nixpkgs;
          nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
          settings = {
            experimental-features = [
              "nix-command"
              "flakes"
              "pipe-operators"
              "auto-allocate-uids"
              "cgroups"
            ];
            auto-allocate-uids = true;

            system-features = [
              "nixos-test"
              "uid-range"
            ];
            auto-optimise-store = true;
            substituters = [
              "https://nix-community.cachix.org"
              "https://cache.nixos-cuda.org"
            ];
            trusted-public-keys = [
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
              "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
            ];
            allow-import-from-derivation = true;
          };
        };
      };
  };
}
