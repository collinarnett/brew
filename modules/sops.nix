{
  config,
  lib,
  ...
}:
{
  users.groups.aws = { };
  sops.defaultSopsFile = ../secrets/secrets.yaml;
  sops.age.sshKeyPaths = [
    "/persist/etc/ssh/ssh_host_ed25519_key"
  ];
  sops.age.keyFile = "/persist/save/home/collin/.config/sops/age/keys.txt";
  sops.secrets.awscli2-config.mode = "0440";
  sops.secrets.awscli2-credentials.mode = "0440";
  sops.secrets.awscli2-config.group = "aws";
  sops.secrets.awscli2-credentials.group = "aws";
  sops.secrets.gcloud-ai-assistant.mode = "0440";
  sops.secrets.gcloud-ai-assistant.owner = "collin";
  sops.secrets.ddclient-config = { };
  sops.secrets.emacs_oai_key.owner = "collin";
  sops.secrets.attic_environment.mode = "0440";
  sops.secrets.gh_token = {
    owner = config.users.users.collin.name;
  };
}
