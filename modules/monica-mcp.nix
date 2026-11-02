{ ... }:
{
  flake.modules.nixos.monica-mcp =
    { config, lib, ... }:
    let
      cfg = config.brew.monica-mcp;
    in
    {
      options.brew.monica-mcp = {
        enable = lib.mkEnableOption "monica-mcp";
      };
      config = lib.mkIf cfg.enable {
        # A personal access token from Monica's Settings → API. Monica issues
        # them for a year, after which this var needs a fresh one.
        clan.core.vars.generators.monica-mcp = {
          files.api_token.owner = config.brew.user;
          prompts.api_token = {
            description = "Monica personal access token for monica-mcp";
            type = "hidden";
            persist = true;
          };
        };

        home-manager.sharedModules = [
          {
            brew.monica-mcp = {
              enable = true;
              apiTokenFile = config.clan.core.vars.generators.monica-mcp.files.api_token.path;
              baseUrl = "https://monica.${config.brew.homelab.domain}";
            };
          }
        ];
      };
    };

  flake.modules.homeManager.monica-mcp =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.monica-mcp;
      tool = name: "mcp__plugin_hm_monica__${name}";
      # Each of these reads; its changes live in the same name plus _edit.
      tools = [
        "monica_contacts"
        "monica_contact_info"
        "monica_relationships"
        "monica_notes"
        "monica_activities"
        "monica_calls"
        "monica_conversations"
        "monica_reminders"
        "monica_tasks"
        "monica_gifts_debts"
        "monica_journal"
        "monica_reference"
        "monica_media"
        "monica_status"
      ];
    in
    {
      options.brew.monica-mcp = {
        enable = lib.mkEnableOption "monica-mcp";
        # A string on purpose: a Nix path literal would copy the token into
        # the world-readable store, and types.str rejects path values.
        apiTokenFile = lib.mkOption {
          type = lib.types.str;
          description = "Runtime path of the file holding the Monica API token.";
        };
        baseUrl = lib.mkOption {
          type = lib.types.str;
          description = "Base URL of the Monica instance, without /api.";
        };
      };
      config = lib.mkIf cfg.enable {
        xdg.configFile."monica-mcp/config.json".text = builtins.toJSON {
          inherit (cfg) baseUrl;
          tokenFile = cfg.apiTokenFile;
        };
        programs.mcp.servers.monica = {
          command = lib.getExe pkgs.monica-mcp;
          args = [
            "--config"
            "${config.xdg.configHome}/monica-mcp/config.json"
          ];
        };
        # Contact records come back alongside mail in the same session, so a
        # change to the CRM always asks first.
        programs.claude-code.settings.permissions = {
          allow = map tool tools;
          ask = map (name: tool "${name}_edit") tools;
        };
      };
    };
}
