{
  sops.defaultSopsFile = ../secrets/secrets.yaml;
  sops.age.keyFile = "/home/collin/.config/sops/age/keys.txt";
  sops.secrets.awscli2-config = { };
  sops.secrets.awscli2-credentials = { };
  sops.secrets.ddclient-config = { };
}
