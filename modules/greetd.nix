{ pkgs, ... }: {
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "sway";
        user = "collin";
      };
    };
  };

}
