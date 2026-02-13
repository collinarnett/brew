{ inputs, ... }:
{
  flake.nixosModules = {
    nix-settings =
      { pkgs, ... }:
      {
        nixpkgs.overlays = [
          inputs.emacs-overlay.overlay
          (import ../overlays inputs)
          (import ../pkgs/all-packages.nix)
        ] ++ (builtins.attrValues (inputs.newt.overlays or {}));
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
            ];
            trusted-public-keys = [
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            ];
            allow-import-from-derivation = true;
          };
        };
      };
  };
}
