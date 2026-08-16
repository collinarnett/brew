{ ... }:
{
  flake.modules.nixos.grocy-mcp =
    { config, lib, ... }:
    let
      cfg = config.brew.grocy-mcp;
    in
    {
      options.brew.grocy-mcp = {
        enable = lib.mkEnableOption "grocy-mcp";
      };
      config = lib.mkIf cfg.enable {
        # The key is scoped to this consumer: grocy issues one API key
        # per client, so revoking grocy-mcp's key cannot break anything
        # else that talks to grocy.
        clan.core.vars.generators.grocy-mcp = {
          share = true;
          files.grocy_api_key = {
            owner = config.brew.user;
          };
          prompts.grocy_api_key = {
            description = "Grocy API key for grocy-mcp";
            type = "hidden";
            persist = true;
          };
        };

        home-manager.sharedModules = [
          {
            brew.grocy-mcp = {
              enable = true;
              grocyApiKeyFile = config.clan.core.vars.generators.grocy-mcp.files.grocy_api_key.path;
            };
          }
        ];
      };
    };

  flake.modules.homeManager.grocy-mcp =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.grocy-mcp;
      tomlFormat = pkgs.formats.toml { };
    in
    {
      options.brew.grocy-mcp = {
        enable = lib.mkEnableOption "grocy-mcp";
        # A string on purpose: a Nix path literal would copy the secret
        # into the world-readable store, and types.str rejects path
        # values outright. Pass the runtime path a secrets manager
        # renders the key at.
        grocyApiKeyFile = lib.mkOption {
          type = lib.types.str;
          description = ''
            Runtime path of the file holding the Grocy API key, rendered
            into the configuration as grocy.api-key-file.
          '';
        };
        grocyUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://grocy.trexd.dev";
          description = "Base URL of the Grocy instance the server operates on.";
        };
      };
      config = lib.mkIf cfg.enable {
        xdg.configFile."grocy-mcp/config.toml".source = tomlFormat.generate "grocy-mcp-config.toml" {
          grocy = {
            url = cfg.grocyUrl;
            "api-key-file" = cfg.grocyApiKeyFile;
          };
        };
        programs.mcp.servers.grocy.command = lib.getExe pkgs.grocy-mcp;
      };
    };
}
