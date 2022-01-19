{
  virtualisation.oci-containers.containers = {
    searx = {
      image = "searx/searx";
      autoStart = true;
      ports = [ "9090:8080" ];
      volumes = [ "/var/cache/searx:/etc/searx" ];
    };
  };
}

