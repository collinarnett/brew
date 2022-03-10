{ pkgs, ... }: {
  programs.qutebrowser = {
    package = pkgs.pinned.qutebrowser;
    enable = true;
  };
}
