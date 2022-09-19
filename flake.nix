{
  description = "NixOS configuration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    mobile-nixpkgs.url =
      "github:nixos/nixpkgs?rev=1670125d5d3e0146d144d316804e3e6fd2f01d43";
    mobile-nixos.url =
      "github:nixOS/mobile-nixos?rev=8a105e177632f0fbc4ca28ee0195993baf0dcf9a";
    mobile-nixos.flake = false;
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, home-manager, nixpkgs, mobile-nixpkgs, sops-nix
    , mobile-nixos, nixos-hardware, ... }@inputs: {
      nixosConfigurations = let
        mkHost = { system ? "x86_64-linux", pkgs ? nixpkgs, user ? "collin"
          , host, extraModules ? [ ] }:
          pkgs.lib.nixosSystem {
            inherit system;
            modules = [
              ./hosts/${host}/configuration.nix
              {
                nix = {
                  registry.pkgs.flake = pkgs;
                  nixPath = [ "nixpkgs=${pkgs}" ];
                };
              }
              sops-nix.nixosModules.sops
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users.${user} = import ./hosts/${host}/home.nix;
              }
            ] ++ extraModules;
          };
      in {
        zombie = mkHost {
          host = "zombie";
        };
        vampire = mkHost { host = "vampire"; };
        pinephone = mkHost {
          system = "aarch64-linux";
          host = "pinephone";
          pkgs = mobile-nixpkgs;
          extraModules = [
            (import "${mobile-nixos}/lib/configuration.nix" {
              device = "pine64-pinephone";
            })
          ];
        };
        arachne = mkHost {
          system = "aarch64-linux";
          host = "arachne";
        };
      };

      pinephone-disk-image =
        (import "${mobile-nixos}/lib/eval-with-configuration.nix" {
          configuration = [ ./hosts/pinephone/configuration.nix ];
          device = "pine64-pinephone";
          pkgs = mobile-nixpkgs.legacyPackages."aarch64-linux";
        }).outputs.disk-image;
    };
}
