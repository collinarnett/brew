{
  services.taskserver = {
    enable = true;
    debug = true;
    ipLog = true;
    organisations.trexd.users = [ "collin" ];
  };
}
