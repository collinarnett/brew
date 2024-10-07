{
  # TODO: Figure out what needs to be added here to get a MVP working
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
        "Downloads"
        "Pictures"
        "Documents"
        "Videos"
        ".config"
      ];
    };
  };
}
