{
  config,
  lib,
  ...
}:
{
  services.restic =
    let
      initialize = true;
      repository = "s3:s3.us-east-1.amazonaws.com/collin-backups/restic";
      passwordFile = config.sops.secrets.restic_s3_password.path;
    in
    {
      backups.media = {
        inherit initialize repository passwordFile;
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
        pruneOpts = [
          "--keep-last 1"
        ];
        paths = [
          "/persist/save/media"
        ];
      };

      backups.org = {
        inherit initialize repository passwordFile;
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
        pruneOpts = [
          "--keep-last 10"
        ];
        paths = [
          "/persist/save/home/collin/org"
        ];
      };

      # Backup for 'projects' and 'work_projects' directories - Daily
      backups.projects = {
        inherit initialize repository passwordFile;
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
        pruneOpts = [
          "--keep-daily 7" # Retain daily snapshots for 1 week
          "--keep-weekly 4" # Retain weekly snapshots for 1 month
          "--keep-monthly 6" # Retain monthly snapshots for 6 months
        ];
        paths = [
          "/persist/save/home/collin/projects"
          "/persist/save/home/collin/work_projects"
        ];
      };

      # Backup for 'Pictures' directory - Weekly
      backups.pictures = {
        inherit initialize repository passwordFile;
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
        };
        pruneOpts = [
          "--keep-weekly 4" # Retain weekly snapshots for 1 month
          "--keep-monthly 6" # Retain monthly snapshots for 6 months
        ];
        paths = [
          "/persist/save/home/collin/Pictures"
        ];
      };

      # Backup for 'Documents' directory - Daily
      backups.documents = {
        inherit initialize repository passwordFile;
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
        pruneOpts = [
          "--keep-daily 7" # Retain daily snapshots for 1 week
          "--keep-weekly 4" # Retain weekly snapshots for 1 month
          "--keep-monthly 12" # Retain monthly snapshots for 1 year
        ];
        paths = [
          "/persist/save/home/collin/Documents"
        ];
      };

      # Backup for 'Videos' directory - Monthly
      backups.videos = {
        inherit initialize repository passwordFile;
        timerConfig = {
          OnCalendar = "monthly";
          Persistent = true;
        };
        pruneOpts = [
          "--keep-last 2" # Retain last two snapshots
        ];
        paths = [
          "/persist/save/home/collin/Videos"
        ];
      };
    };

  systemd.services =
    lib.genAttrs
      [
        "restic-backups-projects"
        "restic-backups-org"
        "restic-backups-pictures"
        "restic-backups-documents"
        "restic-backups-media"
        "restic-backups-videos"
      ]
      (_: {
        environment = {
          AWS_PROFILE = "default";
          AWS_REGION = "us-east-1";
          AWS_SHARED_CREDENTIALS_FILE = config.sops.secrets.awscli2-credentials.path;
        };
      });

  # Define sops secrets for each backup password
  sops.secrets = {
    restic_s3_password = { };
  };
}
