{
  programs.gpg = {
    enable = true;
    settings = {
      use-agent = true;
      pinentry-mode = "loopback";
    };
  };
}
