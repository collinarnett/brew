{
  virtualisation.oci-containers.containers = {
    searx = {
      image = "searx/searx";
      autoStart = true;
      ports = ["8080:8080"];
    };
  };
}
