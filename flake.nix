{
  description = "NixOS configuration";
  inputs = {
    clan-core.url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";
    clan-core.inputs.nixpkgs.follows = "nixpkgs";
    clan-core.inputs.flake-parts.follows = "flake-parts";
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
    nixpkgs-prometheus.url = "github:collinarnett/nixpkgs/dcgm-prometheus-exporter";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    newt.url = "git+file:///home/collin/newt";
    newt.inputs.nixpkgs.follows = "nixpkgs";
    newt.inputs.flake-parts.follows = "flake-parts";
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
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { config, inputs, ... }:
      let
        brewNixosModules = builtins.attrValues config.flake.modules.nixos;
        brewHmModules = builtins.attrValues config.flake.modules.homeManager;
        machineBase = {
          nixpkgs.hostPlatform = "x86_64-linux";
          brew.user = "collin";
          home-manager.sharedModules = brewHmModules;
        };
      in
      {
        imports = [
          inputs.flake-parts.flakeModules.modules
          inputs.clan-core.flakeModules.default
          (inputs.import-tree ./modules)
        ];
        systems = [ "x86_64-linux" ];

        clan = {
          meta.name = "brew";
          inventory.machines = {
            azathoth.deploy.targetHost = "root@azathoth:8787";
            ghoul.deploy = {
              targetHost = "root@ghoul";
              buildHost = "root@azathoth:8787";
            };
            vampire.deploy.targetHost = "root@vampire";
          };
          inventory.instances = {
            sshd-brew = {
              module = {
                name = "sshd";
                input = "clan-core";
              };
              roles.server.tags.all = { };
              roles.server.settings.authorizedKeys = {
                collinarnett = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDq/9Nx7ckExoMDyi2lx5No1Ndv/rz9n83Tyy+yjyaRU collin@zombie";
                ghoul = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAU8UPb5Szy5STfAz8/0KI+RMCVSTvuqcwwEC4RDa1fM collin@ghoul";
                azathoth = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGSPMVlGvq4uWZm1ALkDSoErk1/bhOW4CVhhAWS5J6Gd collin@arnett.it";
              };
              roles.client.tags.all = { };
            };
            yggdrasil = {
              roles.default.tags.all = { };
            };
            internet = {
              roles.default.machines.azathoth.settings = {
                host = "trexd.dev";
              };
            };
          };
          machines = {
            vampire = {
              imports = brewNixosModules ++ [
                ./hosts/vampire/configuration.nix
                machineBase
              ];
            };
            ghoul = {
              imports = brewNixosModules ++ [
                inputs.impermanence.nixosModules.impermanence
                inputs.nixos-facter-modules.nixosModules.facter
                "${gpd-duo-nixos-hardware}/gpd/duo"
                ./hosts/ghoul/configuration.nix
                machineBase
              ];
            };
            azathoth = {
              imports = brewNixosModules ++ [
                inputs.impermanence.nixosModules.impermanence
                inputs.nixos-facter-modules.nixosModules.facter
                ./hosts/azathoth/configuration.nix
                machineBase
              ];
            };
          };
        };

        perSystem =
          { pkgs, ... }:
          {
            formatter = pkgs.nixfmt;
            devShells.default = pkgs.mkShell {
              buildInputs = [
                inputs.clan-core.packages.${pkgs.system}.default
                pkgs.sops
                pkgs.nixfmt
              ];
            };
          };
      }
    );
}
