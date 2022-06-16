{
  description = "NixOS configuration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    mobile-nixpkgs.url =
      "github:nixos/nixpkgs?rev=1670125d5d3e0146d144d316804e3e6fd2f01d43";
    mobile-nixos.url =
      "github:NixOS/mobile-nixos?rev=8a105e177632f0fbc4ca28ee0195993baf0dcf9a";
    mobile-nixos.flake = false;
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";
    pinned-nixpkgs.url =
      "github:nixos/nixpkgs?rev=61d24cba72831201efcab419f19b947cf63a2d61";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, home-manager, nixpkgs, mobile-nixpkgs, sops-nix
    , mobile-nixos, pinned-nixpkgs, nixos-hardware, ... }@inputs: {
      nixosConfigurations = {
        zombie = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/zombie/configuration.nix
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.collin = import ./hosts/zombie/home.nix;
            }
          ];
        };
        pinephone = mobile-nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            {
              nixpkgs.overlays = [
                (final: prev: {
                  pinned = inputs.pinned-nixpkgs.legacyPackages.${prev.system};
                })
              ];

            }
            ./hosts/pinephone/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.collin = import ./hosts/pinephone/home.nix;
            }
            (import "${mobile-nixos}/lib/configuration.nix" {
              device = "pine64-pinephone";
            })
          ];
        };
        arachne = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            nixos-hardware.nixosModules.pine64-pinebook-pro
            {
              nixpkgs.overlays = [
                (final: prev: {
                  pinned = inputs.pinned-nixpkgs.legacyPackages.${prev.system};
                })
              ];
            }
            ./hosts/arachne/configuration.nix
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.collin = import ./hosts/arachne/home.nix;
            }
          ];
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
