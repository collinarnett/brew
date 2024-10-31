{config, ...}: {
  services.restic = {
    backups.media = {
      initialize = true;
      repository = "s3:s3.us-east-1.amazonaws.com/collin-backups";
      passwordFile = config.sops.secrets.restic_media_password.path;
      timerConfig = [
        {
          OnCalendar = "daily";
          Persistent = true;
        }
      ];
      pruneOpts = [
        "--keep-last 1"
      ];
      paths = [
        "/persist/save/media"
      ];
    };
  };
  systemd.services.restic.environment = {
    AWS_PROFILE = "default";
    AWS_REGION = "us-east-1";
    AWS_SHARED_CREDENTIALS_FILE = config.sops.secrets.awscli2-credentials.path;
  };
  sops.secrets.restic_media_password = {
    mode = "0440";
    group = "aws";
  };
}
