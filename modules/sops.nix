{config, ...}: {
  sops.defaultSopsFile = ../secrets/secrets.yaml;
  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
  sops.age.keyFile = "/home/collin/.config/sops/age/keys.txt";
  sops.secrets.awscli2-config.group = "aws";
  sops.secrets.awscli2-credentials.group = "aws";
  sops.secrets.ddclient-config = {};
  sops.secrets.emacs_oai_key.owner = "collin";
  sops.secrets.searx_secret_key = {
    owner = config.systemd.services.traefik.serviceConfig.User;
  };
  sops.secrets.authelia_jwks_settings_file = {
    owner = config.systemd.services.authelia-main.serviceConfig.User;
  };
  sops.secrets.authelia_jwt_secret_file = {
    owner = config.systemd.services.authelia-main.serviceConfig.User;
  };
  sops.secrets.authelia_session_secret_file = {
    owner = config.systemd.services.authelia-main.serviceConfig.User;
  };
  sops.secrets.authelia_storage_encryption_key_file = {
    owner = config.systemd.services.authelia-main.serviceConfig.User;
  };
  sops.secrets.authelia_session_redis_password_file = {};
  sops.secrets.gh_token = {owner = config.users.users.collin.name;};
}
