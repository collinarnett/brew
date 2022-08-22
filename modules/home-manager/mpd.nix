{
  services.mpd = {
    enable = true;
    musicDirectory = "/home/collin/music";
    extraConfig = ''
      audio_output {
        type "alsa"
        name "ALSA"
      }
      audio_output {
        type "fifo"
        name "fifo"
        path "/tmp/mpd.fifo"
        format "44100:16:2"
      }
    '';
  };
}
