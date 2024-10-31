{
  description = "NixOS configuration";
  inputs = {
    disko.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    impermanence.url = "github:nix-community/impermanence";
    nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixpkgs-android.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    home-manager-android = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs-android";
    };
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs-android";
      inputs.home-manager.follows = "home-manager-android";
    };
  };
  outputs = inputs @ {
    self,
    emacs-overlay,
    flake-parts,
    home-manager,
    nixos-hardware,
    sops-nix,
    disko,
    home-manager-android,
    nix-on-droid,
    nixpkgs,
    nixpkgs-android,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} ({
      withSystem,
      inputs,
      ...
    }: {
      imports = [
        ./parts/nixos-modules.nix
      ];
      systems = ["x86_64-linux"];
      flake = {config, ...}: {
        nixOnDroidConfigurations.default = nix-on-droid.lib.nixOnDroidConfiguration {
          modules = [
            ./nix-on-droid/nix-on-droid.nix
          ];
          pkgs = import nixpkgs-android {
            system = "aarch64-linux";
            overlays = [
              nix-on-droid.overlays.default
            ];
          };
          home-manager-path = home-manager-android.outPath;
        };

        nixosConfigurations = let
          genSystem = user: host: extras:
            withSystem "x86_64-linux" ({
              pkgs,
              system,
              ...
            }:
              inputs.nixpkgs.lib.nixosSystem {
                inherit system;

                modules =
                  [
                    config.nixosModules.nix-settings
                    inputs.sops-nix.nixosModules.sops
                    inputs.home-manager.nixosModules.home-manager
                    ./hosts/${host}/configuration.nix
                    {
                      home-manager.useGlobalPkgs = true;
                      home-manager.useUserPackages = true;
                      home-manager.users.${user} = import ./hosts/${host}/home.nix;
                    }
                  ]
                  ++ extras;
              });
        in {
          zombie = genSystem "collin" "zombie" [];
          vampire = genSystem "collin" "vampire" [];
          azathoth = genSystem "collin" "azathoth" [
            inputs.disko.nixosModules.disko
            inputs.impermanence.nixosModules.impermanence
            inputs.nixos-facter-modules.nixosModules.facter
          ];
          arachne = genSystem "collin" "arachne" [
            ./modules/zfs
            "${nixpkgs}/nixos/modules/installer/scan/not-detected.nix"
            "${nixos-hardware}/lenovo/thinkpad/t440p"
          ];
        };
      };
      perSystem = {
        pkgs,
        system,
        ...
      }: {
        formatter = pkgs.alejandra;
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [nil sops alejandra];
        };
      };
    });
}
