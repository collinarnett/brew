{
  description = "NixOS configuration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    mobile-nixpkgs.url = "github:nixos/nixpkgs?rev=23d785aa6f853e6cf3430119811c334025bbef55";
    mobile-nixos.url = "github:NixOS/mobile-nixos?rev=8a105e177632f0fbc4ca28ee0195993baf0dcf9a";
    mobile-nixos.flake = false;
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, home-manager, nixpkgs, mobile-nixpkgs, sops-nix
    , mobile-nixos, ... }@inputs: {
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
        grub = nixpkgs.lib.nixosSystem {
          system = "i686-linux";
          modules = [
            ./hosts/grub/configuration.nix
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.collin = import ./hosts/grub/home.nix;
            }
          ];
        };
        pinephone = mobile-nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
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
      };

      pinephone-disk-image =
        (import "${mobile-nixos}/lib/eval-with-configuration.nix" {
          configuration = [ ./hosts/pinephone/configuration.nix ];
          device = "pine64-pinephone";
          pkgs = mobile-nixpkgs.legacyPackages."aarch64-linux";
        }).outputs.disk-image;
    };
}
