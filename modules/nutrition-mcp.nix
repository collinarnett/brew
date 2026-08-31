{ ... }:
{
  flake.modules.homeManager.nutrition-mcp =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.nutrition-mcp;
      tomlFormat = pkgs.formats.toml { };
    in
    {
      options.brew.nutrition-mcp = {
        enable = lib.mkEnableOption "nutrition-mcp";
        userAgent = lib.mkOption {
          type = lib.types.str;
          default = "nutrition-mcp/0.1 (https://github.com/collinarnett/brew)";
          description = ''
            The User-Agent sent to Open Food Facts, which asks every
            client to identify itself and give a way to reach its operator.
          '';
        };
      };
      config = lib.mkIf cfg.enable {
        xdg.configFile."nutrition-mcp/config.toml".source =
          tomlFormat.generate "nutrition-mcp-config.toml"
            {
              openfoodfacts."user-agent" = cfg.userAgent;
            };
        programs.mcp.servers.nutrition.command = lib.getExe pkgs.nutrition-mcp;
      };
    };
}
