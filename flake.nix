{
  description = "NixOS configuration";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-pinned.url =
      "github:NixOs/nixpkgs?ref=5b091d4fbe3b7b7493c3b46fe0842e4b30ea24b3";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

  };
  outputs = { self, home-manager, nixpkgs, nixpkgs-pinned, sops-nix, ... }@inputs: {
    nixosConfigurations = {
      zombie = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            nixpkgs.overlays = [
              (final: prev: {
                pinned = inputs.nixpkgs-pinned.legacyPackages.${prev.system};
              })
            ];
          }
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
