{ config, lib, ... }:
let
  cfg = config.brew.ollama;
in
{
  options.brew.ollama.enable = lib.mkEnableOption "ollama";
  config = lib.mkIf cfg.enable {
    services.ollama.enable = true;
  };
}
