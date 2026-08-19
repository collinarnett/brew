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
      imports = [
        inputs.home-manager.nixosModules.home-manager
      ]
      ++ builtins.attrValues (inputs.newt.nixosModules or { });

      options.brew.common.enable = lib.mkEnableOption "common profile";

      config = lib.mkIf cfg.enable {
        # Home-manager base setup
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        # Back up pre-existing dotfiles HM wants to manage instead of aborting.
        home-manager.backupFileExtension = "hm-bak";
        home-manager.users.${config.brew.user}.imports = builtins.attrValues (
          inputs.newt.homeManagerModules or { }
        );

        # Nix settings + overlays
        nixpkgs.overlays = [
          inputs.emacs-overlay.overlay
          inputs.claude-code-nix.overlays.default
          inputs.toenail.overlays.default
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
              "ca-derivations"
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
              "https://cache.numtide.com"
            ];
            trusted-public-keys = [
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
              "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
              "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
            ];
            allow-import-from-derivation = true;
          };
        };

        # Stable machine-id across reboots (managed by clan vars)
        clan.core.settings.machine-id.enable = true;

        # Ship terminfo (including xterm-ghostty) so SSHing in from ghostty
        # works without unknown-terminal errors on the remote host.
        environment.enableAllTerminfo = true;

        # Persistent terminal sessions for reattaching over SSH.
        programs.tmux = {
          enable = true;
          # screen advertises 8 colours and no italics; tmux-256color plus the
          # RGB feature below gets 24-bit colour through to the outer terminal.
          terminal = "tmux-256color";
          escapeTime = 10;
          historyLimit = 50000;
          # Clamp only the current window to the smallest attached client, so a
          # session attached from several clients at once stays usable.
          aggressiveResize = true;
          # Bare `tmux` attaches to session 0 rather than creating a duplicate.
          newSession = true;
          extraConfig = ''
            # Without this tmux never requests mouse reporting from the outer
            # terminal, which then falls back to alternate-scroll and delivers
            # the wheel as cursor up/down to full-screen applications.
            set -g mouse on

            set -as terminal-features ",xterm-ghostty:RGB,xterm-256color:RGB"
            set -as terminal-features ",xterm-ghostty:extkeys,xterm-256color:extkeys"

            # Applications requesting extended keys get CSI-u encoding; without
            # it tmux discards Shift-Enter and Ctrl-Enter entirely.
            set -g extended-keys always
            set -g extended-keys-format csi-u

            set -g allow-passthrough on
          '';
        };

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
