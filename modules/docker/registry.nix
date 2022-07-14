{
  virtualisation.oci-containers.containers = {
    registry = {
      image = "registry";
      autoStart = true;
      ports = [ "5000:5000" ];
    };
  };
}

