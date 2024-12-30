{inputs, ...}: {
  flake.nixosModules = {
    nix-settings = {pkgs, ...}: {
      nixpkgs.overlays = [
        inputs.emacs-overlay.overlay
        (import ../overlays)
        (import ../pkgs/all-packages.nix)
      ];
      nixpkgs.config.allowUnfree = true;
      nix = {
        package = pkgs.nixVersions.latest;
        registry.pkgs.flake = inputs.nixpkgs;
        nixPath = ["nixpkgs=${inputs.nixpkgs}"];
        gc = {
          automatic = true;
          randomizedDelaySec = "14m";
          options = "--delete-older-than 10d";
        };
        settings = {
          experimental-features = ["nix-command" "flakes"];
          auto-optimise-store = true;
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
