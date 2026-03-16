{ ... }:
{
  flake.modules.nixos.firefox =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.firefox;
    in
    {
      options.brew.firefox.enable = lib.mkEnableOption "firefox";
      config = lib.mkIf cfg.enable {
        programs.firefox.enable = true;
        programs.firefox.package = pkgs.firefox-esr;
        programs.firefox.policies = {
          SearchEngines = {
            Default = "SearX";
            Remove = [
              "Google"
              "Bing"
              "Amazon.com"
              "eBay"
              "Wikipedia"
            ];
            Add = [
              {
                Name = "SearX";
                URLTemplate = "https://search.trexd.dev/search?q={searchTerms}";
                Method = "GET";
                IconURL = "https://search.trexd.dev/favicon.ico";
                SuggestURLTemplate = "https://search.trexd.dev/autocompleter?q={searchTerms}";
              }
            ];
          };
        };
        home-manager.sharedModules = [
          { brew.firefox.enable = true; }
        ];
      };
    };

  flake.modules.homeManager.firefox =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.firefox;
    in
    {
      options.brew.firefox.enable = lib.mkEnableOption "firefox";
      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.firefox-esr ];
      };
    };
}
