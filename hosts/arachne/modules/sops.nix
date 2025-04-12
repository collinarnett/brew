{ config, ... }:
{
  sops.defaultSopsFile = ../../../secrets/secrets.yaml;
  sops.age.keyFile = "/home/collin/.config/sops/age/keys.txt";
  sops.secrets.gh_token = {
    owner = config.users.users.collin.name;
  };
}
