{ pkgs, ... }:
{
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
}
