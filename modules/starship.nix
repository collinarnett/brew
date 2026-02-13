{ config, lib, ... }:
let
  cfg = config.brew.starship;
  user = config.brew.user;
in
{
  options.brew.starship.enable = lib.mkEnableOption "starship" // {
    default = true;
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${user} = {
      programs.starship = {
        enable = true;
        enableZshIntegration = true;
        settings = {
          character = {
            success_symbol = "[\\$](bold #8be9fd)";
            error_symbol = "[\\$](bold #ff5555)";
          };
          username = {
            style_user = "bold #ff79c6";
          };
          hostname = {
            style = "bold #50fa7b";
          };
        };
      };
    };
  };
}
