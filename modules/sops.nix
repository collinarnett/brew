{ ... }:
{
  flake.modules.nixos.sops =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.brew.sops;
    in
    {
      options.brew.sops.enable = lib.mkEnableOption "sops";
      options.brew.gh-token.enable = lib.mkEnableOption "gh_token";

      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          users.groups.aws = { };

          clan.core.vars.generators.awscli2-config = {
            files.awscli2-config = {
              group = "aws";
              mode = "0440";
            };
            prompts.awscli2-config = {
              description = "AWS CLI config file contents";
              type = "multiline";
              persist = true;
            };
          };

          clan.core.vars.generators.awscli2-credentials = {
            files.awscli2-credentials = {
              group = "aws";
              mode = "0440";
            };
            prompts.awscli2-credentials = {
              description = "AWS CLI credentials file contents";
              type = "multiline";
              persist = true;
            };
          };

          clan.core.vars.generators.gcloud-ai-assistant = {
            files.gcloud-ai-assistant = {
              owner = "collin";
              mode = "0440";
            };
            prompts.gcloud-ai-assistant = {
              description = "GCloud AI assistant credentials";
              type = "multiline";
              persist = true;
            };
          };

          clan.core.vars.generators.ddclient-config = {
            files.ddclient-config = { };
            prompts.ddclient-config = {
              description = "ddclient configuration file contents";
              type = "multiline";
              persist = true;
            };
          };

          clan.core.vars.generators.emacs_oai_key = {
            files.emacs_oai_key = {
              owner = "collin";
            };
            prompts.emacs_oai_key = {
              description = "OpenAI API key for Emacs";
              type = "hidden";
              persist = true;
            };
          };

          clan.core.vars.generators.attic_environment = {
            files.attic_environment = {
              mode = "0440";
            };
            prompts.attic_environment = {
              description = "Attic environment file contents";
              type = "multiline";
              persist = true;
            };
          };
        })

        (lib.mkIf config.brew.gh-token.enable {
          clan.core.vars.generators.gh_token = {
            share = true;
            files.gh_token = {
              owner = "collin";
            };
            prompts.gh_token = {
              description = "GitHub personal access token";
              type = "hidden";
              persist = true;
            };
          };
        })
      ];
    };
}
