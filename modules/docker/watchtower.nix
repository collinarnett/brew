{
  virtualisation.oci-containers.containers.watchtower = {
    image = "containrrr/watchtower";
    volumes = [ "/var/run/docker.sock:/var/run/docker.sock" ];
  };

}
