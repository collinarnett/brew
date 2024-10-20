{
  environment.persistence."/persist" = {
    directories = [
      "/var/log"
      "/var/lib/libvirt"
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
        {
          directory = ".config/sops/age/";
          mode = "0700";
        }
        {
          directory = ".ssh";
          mode = "0700";
        }
        ".local/share/direnv"
      ];
    };
  };
}
