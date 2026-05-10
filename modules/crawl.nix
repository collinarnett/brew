{ ... }:
{
  flake.modules.homeManager.crawl =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.crawl;
    in
    {
      options.brew.crawl.enable = lib.mkEnableOption "crawl";
      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.crawl ];
        home.file.".crawlrc".source = ../configurations/crawl/crawlrc;
      };
    };
}
