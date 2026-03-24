{ inputs, ... }:
{
  flake.modules.nixos.common =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.common;
    in
    {
      imports =
        [
          inputs.home-manager.nixosModules.home-manager
        ]
        ++ builtins.attrValues (inputs.newt.nixosModules or { });

      options.brew.common.enable = lib.mkEnableOption "common profile";

      config = lib.mkIf cfg.enable {
        # Home-manager base setup
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.${config.brew.user}.imports =
          builtins.attrValues (inputs.newt.homeManagerModules or { });

        # Nix settings + overlays
        nixpkgs.overlays =
          [
            inputs.emacs-overlay.overlay
            (import ../overlays inputs)
            (import ../pkgs/all-packages.nix)
          ]
          ++ builtins.attrValues (inputs.newt.overlays or { });
        nixpkgs.config.allowUnfree = true;
        nix = {
          package = pkgs.nixVersions.latest;
          registry.pkgs.flake = inputs.nixpkgs;
          nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
          settings = {
            experimental-features = [
              "nix-command"
              "flakes"
              "pipe-operators"
              "auto-allocate-uids"
              "cgroups"
            ];
            auto-allocate-uids = true;
            system-features = [
              "nixos-test"
              "uid-range"
            ];
            auto-optimise-store = true;
            substituters = [
              "https://nix-community.cachix.org"
              "https://cache.nixos-cuda.org"
            ];
            trusted-public-keys = [
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
              "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
            ];
            allow-import-from-derivation = true;
          };
        };

        # Stable machine-id across reboots (managed by clan vars)
        clan.core.settings.machine-id.enable = true;

        # NixOS-level enables for mixed modules
        brew.keychain.enable = true;

        # Forward to HM
        home-manager.sharedModules = [ { brew.common.enable = true; } ];
      };
    };

  flake.modules.homeManager.common =
    { config, lib, ... }:
    let
      cfg = config.brew.common;
    in
    {
      options.brew.common.enable = lib.mkEnableOption "common profile";
      config = lib.mkIf cfg.enable {
        brew = {
          autojump.enable = true;
          bat.enable = true;
          btop.enable = true;
          direnv.enable = true;
          fzf.enable = true;
          gh.enable = true;
          git.enable = true;
          gpg.enable = true;
          gpg-agent.enable = true;
          keychain.enable = true;
          starship.enable = true;
          zoxide.enable = true;
          zsh.enable = true;
        };
      };
    };
}
