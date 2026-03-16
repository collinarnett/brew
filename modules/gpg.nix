{ ... }:
{
  flake.modules.homeManager.gpg =
    { config, lib, ... }:
    let
      cfg = config.brew.gpg;
    in
    {
      options.brew.gpg.enable = lib.mkEnableOption "gpg";
      config = lib.mkIf cfg.enable {
        programs.gpg = {
          enable = true;
          settings = {
            use-agent = true;
            pinentry-mode = "ask";
          };
        };
      };
    };
}
