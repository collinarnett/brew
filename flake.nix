{
  description = "NixOS configuration";
  inputs = {
    clan-core.url = "git+https://git.clan.lol/collinarnett/clan-core?ref=fix/yggdrasil-export-hostname";
    clan-core.inputs.nixpkgs.follows = "nixpkgs";
    clan-core.inputs.flake-parts.follows = "flake-parts";
    claude-code-nix.url = "github:sadjow/claude-code-nix";
    claude-code-nix.inputs.nixpkgs.follows = "nixpkgs";
    dracula-signal.url = "github:dracula/signal-desktop";
    dracula-signal.inputs.nixpkgs.follows = "nixpkgs";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    gpd-duo-nixos-hardware.url = "github:/shymega/nixos-hardware/add-gpd-duo";
    gpd-duo-nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";
    hell.url = "github:chrisdone/hell";
    hell.inputs.nixpkgs.follows = "nixpkgs";
    hermes-agent.url = "github:NousResearch/hermes-agent";
    hermes-agent.inputs.nixpkgs.follows = "nixpkgs";
    hermes-agent.inputs.flake-parts.follows = "flake-parts";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    mcp-servers-nix.url = "github:natsukium/mcp-servers-nix";
    mcp-servers-nix.inputs.nixpkgs.follows = "nixpkgs";
    import-tree.url = "github:vic/import-tree";
    impermanence.url = "github:nix-community/impermanence";
    impermanence.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.inputs.home-manager.follows = "home-manager";
    nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";
    nixos-anywhere.inputs.flake-parts.follows = "flake-parts";
    nixos-anywhere.inputs.disko.follows = "clan-core/disko";
    nixos-anywhere.inputs.treefmt-nix.follows = "clan-core/treefmt-nix";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixpkgs-prometheus.url = "github:collinarnett/nixpkgs/dcgm-prometheus-exporter";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-topology.url = "github:oddlama/nix-topology";
    nix-topology.inputs.nixpkgs.follows = "nixpkgs";
    toenail.url = "git+https://garden.trexd.dev/z3PyS59SMW9PRoyz8MSpG2gXiPnq1.git?ref=refs/tags/v0.8.0";
    toenail.inputs.nixpkgs.follows = "nixpkgs";
    newt.url = "git+file:///home/collin/newt";
    newt.inputs.nixpkgs.follows = "nixpkgs";
    newt.inputs.flake-parts.follows = "flake-parts";
    newt.inputs.import-tree.follows = "import-tree";
    tuicr.url = "github:agavra/tuicr";
    tuicr.inputs.nixpkgs.follows = "nixpkgs";
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
          # The iroh tunnel exposes sshd to the whole iroh network, leaving
          # SSH authentication as the only barrier. PAM's keyboard-interactive
          # path accepts user passwords even with PasswordAuthentication off,
          # so disable it to keep logins strictly key-based.
          services.openssh.settings.KbdInteractiveAuthentication = false;
          home-manager.sharedModules = brewHmModules ++ [
            inputs.mcp-servers-nix.homeManagerModules.default
          ];
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
                vampire = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICJAakPne69SzkRrlQBBP6m8OZni83eDiq+Et2iruSQA collin@arnett.it";
              };
              roles.client.tags.all = { };
            };
            yggdrasil = {
              roles.default.tags.all = { };
              # Direct LAN peering; UDP 9001 + TCP 5400 opened in host firewall.
              roles.default.machines.azathoth.settings.multicastInterfaces = [
                {
                  Regex = "eno2";
                  Beacon = true;
                  Listen = true;
                  Port = 5400;
                  Priority = 0;
                }
              ];
              roles.default.settings = {
                extraPeers = [
                  "tls://mo.us.ygg.triplebit.org:993"
                  "tls://mn.us.ygg.triplebit.org:993"
                  "tls://ygg-pa.incognet.io:8884"
                ];
                extraYggdrasilIPs = [
                  # Phone
                  "201:746b:a9c:402a:6a45:a9fe:ab4c:9ffa"
                ];
              };
            };
            # NAT-traversing SSH over iroh (dumbpipe): `clan ssh` falls back
            # to it when direct and yggdrasil routes fail, so machines stay
            # reachable without exposing sshd to the internet.
            iroh = {
              module = {
                name = "p2p-ssh-iroh";
                input = "clan-core";
              };
              roles.server.machines.azathoth = { };
            };
          };
          machines = {
            vampire = {
              imports = brewNixosModules ++ [
                ./hosts/vampire/configuration.nix
                machineBase
              ];
              clan.core.networking.buildHost = "root@azathoth.clan";
              clan.core.networking.forwardAgent = true;
            };
            ghoul = {
              imports = brewNixosModules ++ [
                inputs.impermanence.nixosModules.impermanence
                inputs.nixos-facter-modules.nixosModules.facter
                "${gpd-duo-nixos-hardware}/gpd/duo"
                ./hosts/ghoul/configuration.nix
                machineBase
              ];
              clan.core.networking.buildHost = "root@azathoth.clan";
              clan.core.networking.forwardAgent = true;
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
            devShells.default =
              let
                # The overlay defines the local packages and the mcp-server
                # fork; building the shell from it keeps cabal compiling
                # against the same dependency versions the machines deploy.
                brewPkgs = pkgs.extend (import ./pkgs/all-packages.nix);
                localPkgs = [
                  "browser-cookies"
                  "clan-mcp"
                  "walmart"
                  "walmart-extractor"
                  "walmart-mcp"
                  "grocy"
                  "grocy-mcp"
                  "openfoodfacts"
                  "nutrition-mcp"
                ];
              in
              brewPkgs.haskellPackages.shellFor {
                packages = ps: map (name: ps.${name}) localPkgs;
                nativeBuildInputs = with pkgs; [
                  inputs.clan-core.packages.${pkgs.stdenv.hostPlatform.system}.default
                  sops
                  nixfmt
                  cabal-install
                  haskellPackages.haskell-language-server
                  haskellPackages.stan
                ];
              };
          };
      }
    );
}
