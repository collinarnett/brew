{
  services.mpd = {
    enable = true;
    musicDirectory = "/home/collin/music";
    network = {
      listenAddress = "127.0.0.1";
      port = 6600;
    };
    extraConfig = ''
      audio_output {
        type "pulse"
        name "Pulseaudio"
        device "pulse"
        mixer_type "hardware"
      }
    '';
  };
}
