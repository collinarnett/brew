{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.brew.pipewire;
in
{
  options.brew.pipewire.enable = lib.mkEnableOption "pipewire";
  config = lib.mkIf cfg.enable {
    services.pipewire = {
      enable = true;
      jack.enable = true;
      alsa.enable = true;
      pulse.enable = true;
      socketActivation = true;
    };
    environment.systemPackages = with pkgs; [
      pavucontrol
      helvum
    ];
  };
}
