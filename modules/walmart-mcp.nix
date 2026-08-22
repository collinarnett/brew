{ ... }:
{
  flake.modules.homeManager.walmart-mcp =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.walmart-mcp;
      tomlFormat = pkgs.formats.toml { };
    in
    {
      options.brew.walmart-mcp = {
        enable = lib.mkEnableOption "walmart-mcp";
        seededOperations = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {
            PurchaseHistoryV2 = "a7067e4c7c36457fdef25b48d8c1ab5574f2e5f64580cdd5b1202b32c39928f6";
            getOrder = "d0622497daef19150438d07c506739d451cad6749cf45c3b4db95f2f5a0a65c4";
          };
          description = ''
            Persisted query hashes keyed by the operation name Walmart's
            gateway knows.

            The client discovers hashes from Walmart's current frontend
            build and refreshes them itself, so an operation belongs here
            only when it is absent from those bundles: getOrder is
            registered server-side and never shipped to the browser, and
            PurchaseHistoryV2 loads from a bundle Walmart serves only on
            pages its bot protection withholds. A hash is public data, not
            a secret.
          '';
        };
      };
      config = lib.mkIf cfg.enable {
        xdg.configFile."walmart-mcp/config.toml".source = tomlFormat.generate "walmart-mcp-config.toml" {
          operation = lib.mapAttrsToList (name: hash: { inherit name hash; }) cfg.seededOperations;
        };
        home.packages = [ pkgs.walmart-extractor ];
        programs.mcp.servers.walmart.command = lib.getExe pkgs.walmart-mcp;
      };
    };
}
