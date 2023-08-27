{
  description = "NixOS configuration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = {
    self,
    emacs-overlay,
    home-manager,
    nixos-hardware,
    nixpkgs,
    sops-nix,
    ...
  }: {
    nixosConfigurations = let
      mkHost = {
        system ? "x86_64-linux",
        user ? "collin",
        host,
        extraModules ? [],
      }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = let
            pkgs = nixpkgs.legacyPackages.${system};
          in
            [
              ./hosts/${host}/configuration.nix
              {
                nix = {
                  package = pkgs.nixUnstable;
                  registry.pkgs.flake = nixpkgs;
                  nixPath = ["nixpkgs=${nixpkgs}"];
                  settings = {
                    substituters = [
                      "https://nix-community.cachix.org"
                    ];
                    trusted-public-keys = [
                      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
                    ];
                  };
                };
                nixpkgs.overlays = [emacs-overlay.overlay];
              }

              sops-nix.nixosModules.sops
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users.${user} = import ./hosts/${host}/home.nix;
              }
            ]
            ++ extraModules;
        };
    in {
      zombie = mkHost {
        host = "zombie";
      };
      vampire = mkHost {host = "vampire";};
      arachne = mkHost {
        host = "arachne";
        extraModules = [
          ./modules/zfs
          {
            imports = [
              "${nixpkgs}/nixos/modules/installer/scan/not-detected.nix"
              "${nixos-hardware}/lenovo/thinkpad/t440p"
            ];
          }
        ];
      };
    };
    formatter."x86_64-linux" = nixpkgs.legacyPackages."x86_64-linux".alejandra;
    devShells."x86_64-linux".default = nixpkgs.legacyPackages."x86_64-linux".mkShell {
      buildInputs = with nixpkgs.legacyPackages."x86_64-linux"; [nil alejandra];
    };
  };
}
