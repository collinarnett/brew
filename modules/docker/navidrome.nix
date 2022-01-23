{
  virtualisation.oci-containers.containers.navidrome = {
    image = "deluan/navidrome";
    ports = [ "4533:4533" ];
    volumes = [ "/var/lib/navidrome/:/data" "/home/collin/music:/music:ro" ];
    environment = {
      ND_SCANSCHEDULE = "1h";
      ND_LOGLEVEL = "info";
      ND_SESSIONTIMEOUT = "24h";
      ND_REVERSEPROXYUSERHEADER = "X-Forwarded-User";
      ND_REVERSEPROXYWHITELIST = "http://127.0.0.1";
    };
  };

}
