{
  environment.persistence."/persist" = {
    directories = [
      "/var/cache/restic-backups-data"
      "/var/cache/restic-backups-state"
      "/var/log"
      "/var/lib/libvirt"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/"
      "/run/secrets.d"
      {
        directory = "/var/lib/traefik";
        user = "traefik";
        group = "traefik";
        mode = "0700";
      }
      {
        directory = "/var/lib/jellyfin";
        user = "jellyfin";
        group = "jellyfin";
        mode = "0700";
      }
      {
        directory = "/var/lib/authelia-main";
        user = "authelia-main";
        group = "authelia-main";
        mode = "0700";
      }
    ];
  };
  users.groups.multimedia = {};
  environment.persistence."/persist/save" = {
    directories = [
      {
        directory = "/media";
        group = "multimedia";
        mode = "0770";
      }
    ];
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
