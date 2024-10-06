{
  # TODO: Figure out what needs to be added here to get a MVP working
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
