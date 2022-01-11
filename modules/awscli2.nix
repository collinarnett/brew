# WIP
{ config, lib, pkgs, ... }:

with lib;

let cfg = config.programs.awscli2;
in {

  options.programs.awscli2 = with lib.types; {
    enable = mkEnableOption "Awscli2";

    config = mkOption {
      type = nullOr path;
      default = null;
    };

    credentials = mkOption {
      type = nullOr path;
      default = null;
    };

  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.awscli2 ];

    xdg.configFile."awscli2/config" =
      mkIf (cfg.config != null) { source = cfg.config; };

    xdg.configFile."awscli2/credentials" =
      mkIf (cfg.config != null) { source = cfg.credentials; };
  };
}

