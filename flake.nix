{
  description = "NixOS configuration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    mobile-nixpkgs.url =
      "github:nixos/nixpkgs?rev=32096899af23d49010bd8cf6a91695888d9d9e73";
    mobile-nixos.url =
      "github:collinarnett/mobile-nixos/witch";
    mobile-nixos.flake = false;
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
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
        witch = mkHost {
          system = "aarch64-linux";
          host = "witch";
          pkgs = mobile-nixpkgs;
          extraModules = [
            (import "${mobile-nixos}/lib/configuration.nix" {
              device = "pine64-pinephone";
            })
	    "${mobile-nixos}/examples/phosh/phosh.nix"
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
