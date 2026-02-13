{
  environment.persistence."/persist" = {
    directories = [
      "/etc/NetworkManager/system-connections"
      "/var/cache/restic-backups-data"
      "/var/cache/restic-backups-state"
      "/var/lib/NetworkManager"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/log"
    ];
  };
  users.groups.multimedia = { };
  environment.persistence."/persist/save" = {
    users.collin = {
      directories = [
        ".config/pulse"
        ".config/Signal"
        ".local/share/direnv"
        ".local/share/Steam"
        ".mozilla"
        "Documents"
        "Downloads"
        "Pictures"
        "Videos"
        "brew"
        "newt"
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
