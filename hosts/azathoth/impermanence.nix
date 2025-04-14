{
  environment.persistence."/persist" = {
    directories = [
      "/var/cache/restic-backups-data"
      "/var/cache/restic-backups-state"
      "/var/log"
      "/var/lib/libvirt"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
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
        directory = "/var/lib/calibre-web";
        user = "calibre-web";
        group = "calibre-web";
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
  users.groups.multimedia = { };
  environment.persistence."/persist/save" = {
    directories = [
      {
        directory = "/media";
        group = "multimedia";
        mode = "0770";
      }
    ];
    files = [
      "/root/.ssh/remotebuild"
      "/root/.ssh/remotebuild.pub"
    ];
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
