{pkgs, ...}: {
  programs.ssh = {
    enable = true;
    serverAliveInterval = 60;
  };
}
