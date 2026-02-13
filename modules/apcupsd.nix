{ config, lib, ... }:
let
  cfg = config.brew.apcupsd;
in
{
  options.brew.apcupsd.enable = lib.mkEnableOption "apcupsd";
  config = lib.mkIf cfg.enable {
    services.apcupsd = {
      enable = true;
    };
  };
}
