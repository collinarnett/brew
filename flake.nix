{
  description = "NixOS configuration";
  inputs = {
    disko.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    flake-parts.url = "github:hercules-ci/flake-parts";
    gpd-duo-nixos-hardware.url = "github:/shymega/nixos-hardware/add-gpd-duo";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    import-tree.url = "github:vic/import-tree";
    impermanence.url = "github:nix-community/impermanence";
    nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    newt.url = "git+file:///home/collin/newt";
    newt.inputs.nixpkgs.follows = "nixpkgs";
    newt.inputs.flake-parts.follows = "flake-parts";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
  };
  outputs =
    inputs@{
      self,
      emacs-overlay,
      flake-parts,
      home-manager,
      import-tree,
      newt,
      nixos-hardware,
      gpd-duo-nixos-hardware,
      sops-nix,
      disko,
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      {
        withSystem,
        inputs,
        ...
      }:
      {
        imports = [
          ./parts/nixos-modules.nix
        ];
        systems = [ "x86_64-linux" ];
        flake =
          { config, ... }:
          {
            nixosConfigurations =
              let
                genSystem =
                  user: host: extras:
                  withSystem "x86_64-linux" (
                    {
                      pkgs,
                      system,
                      ...
                    }:
                    inputs.nixpkgs.lib.nixosSystem {
                      inherit system;

                      modules = [
                        (inputs.import-tree ./modules)
                        config.nixosModules.nix-settings
                        inputs.sops-nix.nixosModules.sops
                        inputs.home-manager.nixosModules.home-manager
                        ./hosts/${host}/configuration.nix
                        {
                          brew.user = user;
                          home-manager.useGlobalPkgs = true;
                          home-manager.useUserPackages = true;
                          home-manager.users.${user}.imports = builtins.attrValues (inputs.newt.homeManagerModules or { });
                        }
                      ]
                      ++ (builtins.attrValues (inputs.newt.nixosModules or { }))
                      ++ extras;
                    }
                  );
              in
              {
                vampire = genSystem "collin" "vampire" [ ];
                ghoul = genSystem "collin" "ghoul" [
                  inputs.disko.nixosModules.disko
                  inputs.impermanence.nixosModules.impermanence
                  inputs.nixos-facter-modules.nixosModules.facter
                  "${gpd-duo-nixos-hardware}/gpd/duo"
                ];
                azathoth = genSystem "collin" "azathoth" [
                  inputs.disko.nixosModules.disko
                  inputs.impermanence.nixosModules.impermanence
                  inputs.nixos-facter-modules.nixosModules.facter
                ];
              };
          };
        perSystem =
          {
            pkgs,
            system,
            ...
          }:
          {
            formatter = pkgs.nixfmt;
            devShells.default = pkgs.mkShell {
              buildInputs = with pkgs; [
                sops
                nixfmt
              ];
            };
          };
      }
    );
}
