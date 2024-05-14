{
  services.mpd = {
    enable = true;
    musicDirectory = "/media/music/music";
    extraConfig = ''
      audio_output {
        type "pulse"
        name "pulse audio"
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
