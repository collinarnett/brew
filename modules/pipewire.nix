{ ... }:
{
  flake.modules.nixos.pipewire =
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
          wireplumber.extraConfig."10-bluez" = {
            "monitor.bluez.properties" = {
              "bluez5.auto-connect" = [
                "a2dp_sink"
                "a2dp_source"
              ];
            };
          };
        };
        environment.systemPackages = with pkgs; [
          pavucontrol
          helvum
        ];
      };
    };
}
