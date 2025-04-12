{
  programs.beets = {
    enable = true;
    settings = {
      directory = "/media/music/";
      plugins = [ "fetchart" ];
    };
  };
}
