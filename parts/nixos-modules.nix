{inputs, ...}: {
  flake.nixosModules = {
    nix-settings = {pkgs, ...}: {
      nixpkgs.overlays = [
        inputs.emacs-overlay.overlay
        (import ../overlays/python.nix)
        (import ../pkgs/all-packages.nix)
      ];
      nix = {
        package = pkgs.nixVersions.latest;
        registry.pkgs.flake = inputs.nixpkgs;
        nixPath = ["nixpkgs=${inputs.nixpkgs}"];
        settings = {
          substituters = [
            "https://nix-community.cachix.org"
          ];
          trusted-public-keys = [
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          ];
        };
      };
    };
  };
}
