{
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers = {
    searx = {
      image = "searx/searx";
      autoStart = true;
      ports = [ "80:8080" ];
      volumes = [ "/home/collin/.searx:/etc/searx" ];
      environment = { BASE_URL = "http://localhost:80/"; };
    };
  };
}

