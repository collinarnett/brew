{ config, ... }:

{
  sops.defaultSopsFile = ../secrets/secrets.yaml;
  sops.age.keyFile = "/home/collin/.config/sops/age/keys.txt";
  sops.secrets.awscli2-config = { };
  sops.secrets.awscli2-credentials = { };
  sops.secrets.ddclient-config = { };
  sops.secrets.searx_secret_key = { };
  sops.secrets.gh_token = { owner=config.users.users.collin.name; };
}
