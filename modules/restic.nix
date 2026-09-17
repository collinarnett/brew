{ ... }:
{
  flake.modules.nixos.restic =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.brew.restic;
    in
    {
      options.brew.restic.enable = lib.mkEnableOption "restic";
      config = lib.mkIf cfg.enable {
        clan.core.vars.generators.restic_s3_password = {
          files.restic_s3_password = { };
          prompts.restic_s3_password = {
            description = "Restic S3 repository password";
            type = "hidden";
            persist = true;
          };
        };

        # Credentials for the backup bucket alone. The IAM user behind
        # them can only read and write objects under the restic prefix of
        # collin-backups, so a leak from a backup job reaches no other
        # bucket and nothing else in the account.
        clan.core.vars.generators.restic-aws-credentials = {
          files.restic-aws-credentials = { };
          prompts.restic-aws-credentials = {
            description = "AWS credentials file contents for the restic S3 repository";
            type = "multiline";
            persist = true;
          };
        };

        services.restic =
          let
            initialize = true;
            repository = "s3:s3.us-east-1.amazonaws.com/collin-backups/restic";
            passwordFile = config.clan.core.vars.generators.restic_s3_password.files.restic_s3_password.path;

            # Every job writes to the one repository above. A backup takes a
            # shared lock, but the `forget --prune` that follows it needs an
            # exclusive lock, which no other job's shared lock can coexist
            # with. Each job therefore gets its own slot, spaced far wider
            # than the longest run so a prune never meets a sibling's backup.
            schedule = onCalendar: {
              OnCalendar = onCalendar;
              Persistent = true;
            };
          in
          {
            backups.media = {
              inherit initialize repository passwordFile;
              timerConfig = schedule "*-*-* 00:00:00";
              pruneOpts = [
                "--keep-last 1"
              ];
              paths = [
                "/persist/save/media"
              ];
            };

            backups.org = {
              inherit initialize repository passwordFile;
              timerConfig = schedule "*-*-* 00:15:00";
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
              timerConfig = schedule "*-*-* 00:30:00";
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
              timerConfig = schedule "Mon *-*-* 01:00:00";
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
              timerConfig = schedule "*-*-* 00:45:00";
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
              timerConfig = schedule "*-*-01 01:15:00";
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
                AWS_SHARED_CREDENTIALS_FILE =
                  config.clan.core.vars.generators.restic-aws-credentials.files.restic-aws-credentials.path;
              };
            });

      };
    };
}
