{ nixosConfig, ... }:

{
  programs.awscli2 = {
    enable = true;
    config = nixosConfig.sops.secrets.awscli2-config.path;
    credentials = nixosConfig.sops.secrets.awscli2-credentials.path;
  };
}
