{
  environment.persistence."/persist" = {
    directories = [
      "/var/cache/restic-backups-data"
      "/var/cache/restic-backups-state"
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
    ];
  };
  users.groups.multimedia = { };
  environment.persistence."/persist/save" = {
    users.collin = {
      directories = [
        ".config/Signal"
        ".local/share/direnv"
        ".mozilla"
        "Documents"
        "Downloads"
        "Pictures"
        "Videos"
        "brew"
        "misc"
        "org"
        "projects"
        "work_projects"
        {
          directory = ".gnupg";
          mode = "0700";
        }
        {
          directory = "keys";
          mode = "0700";
        }
        {
          directory = ".config/sops/age/";
          mode = "0700";
        }
        {
          directory = ".ssh";
          mode = "0700";
        }
      ];
      files = [
        ".zsh_history"
      ];
    };
  };
}
