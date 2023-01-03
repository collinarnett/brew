{
  programs.beets = {
    enable = true;
    settings = {
      directory = "/home/collin/music/";
      plugins = ["fetchart"];
    };
  };
}
