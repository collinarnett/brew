{ ... }:
{
  flake.modules.nixos.homelab =
    {
      config,
      lib,
      ...
    }:
    let
      inherit (lib)
        mkIf
        mkEnableOption
        mkOption
        types
        ;
      cfg = config.brew.homelab;
    in
    {
      imports = [
        ./_crowdsec.nix
        ./_grocy.nix
        ./_homepage.nix
        ./_jellyfin.nix
        ./_kanidm.nix
        ./_kavita.nix
        ./_nginx.nix
        ./_oauth2-proxy.nix
        ./_radicle.nix
        ./_rqbit.nix
        ./_searx.nix
      ];

      options.brew.homelab = {
        enable = mkEnableOption "homelab";
        crowdsec = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "crowdsec";
            };
          };
        };
        grocy = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "grocy";
            };
          };
        };
        homepage = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "homepage";
            };
          };
        };
        jellyfin = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "jellyfin";
            };
          };
        };
        kanidm = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "kanidm";
            };
          };
        };
        kavita = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "kavita";
            };
          };
        };
        radicle = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "radicle";
              follow = mkOption {
                type = types.listOf types.str;
                default = [ ];
                example = [ "did:key:z6MkjE3BSJn4Y129rhqi5rViSUru8KSBcCQdQcDZq1cnjumw" ];
                description = ''
                  DIDs to follow. The seed accepts and periodically
                  auto-seeds every repository these identities publish.
                '';
              };
              seedRepositories = mkOption {
                type = types.listOf types.str;
                default = [ ];
                example = [ "rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5" ];
                description = ''
                  Repository IDs to seed unconditionally and pin in the
                  web UI.
                '';
              };
            };
          };
        };
        rqbit = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "rqbit";
            };
          };
        };
        searx = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "searx";
            };
          };
        };
        nginx = mkOption {
          default = { };
          type = types.submodule {
            options = {
              enable = mkEnableOption "nginx";
            };
          };
        };
      };

      config = mkIf cfg.enable {
        users.groups.multimedia = { };
        systemd.tmpfiles.rules = [
          "d /media 0770 - multimedia - -"
        ];

        # Credentials for the DNS-01 challenge, shared by every vhost
        # certificate and by kanidm's. The IAM user behind them may only
        # write _acme-challenge TXT records in the trexd.dev zone, so a
        # leak cannot redirect a hostname or reach the rest of the
        # account.
        clan.core.vars.generators.acme-aws-credentials = {
          files.acme-aws-credentials = {
            group = "acme";
            mode = "0440";
          };
          prompts.acme-aws-credentials = {
            description = "AWS credentials file contents for the ACME route53 challenge";
            type = "multiline";
            persist = true;
          };
        };
      };
    };
}
