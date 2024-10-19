{
  environment.persistence."/persist" = {
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
    ];
  };
  environment.persistence."/persist/save" = {
    users.collin = {
      directories = [
        "brew"
        "projects"
        "work_projects"
        "Downloads"
        "Pictures"
        "Documents"
        "Videos"
        ".config"
      ];
    };
  };
}
