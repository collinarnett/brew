{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    sops-nix.url = "github:Mic92/sops-nix";
  };
  outputs = { self, home-manager, nixpkgs, sops-nix, ... }: {
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
    };
  };
}
