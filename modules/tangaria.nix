{ ... }:
{
  flake.modules.homeManager.tangaria =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.tangaria;
    in
    {
      options.brew.tangaria.enable = lib.mkEnableOption "tangaria";
      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.tangaria ];
        home.file.".pwmangrc".source = ../configurations/tangaria/pwmangrc;
      };
    };
}
