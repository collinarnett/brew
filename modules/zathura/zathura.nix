{ ... }:
{
  flake.modules.homeManager.zathura =
    { config, lib, ... }:
    let
      cfg = config.brew.zathura;
    in
    {
      options.brew.zathura.enable = lib.mkEnableOption "zathura";
      config = lib.mkIf cfg.enable {
        programs.zathura = {
          enable = true;
          options = {
            selection-clipboard = "clipboard";
          };
          extraConfig = builtins.readFile ./zathurarc;
        };
      };
    };
}
