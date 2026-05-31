{
  # Point sops-nix at the persist path directly so the age key is available
  # during initrd activation (before impermanence bind mounts are set up).
  clan.core.vars.sops.secretUploadDirectory = "/persist/var/lib/sops-nix";

  environment.persistence."/persist" = {
    directories = [
      "/var/cache/restic-backups-data"
      "/var/cache/restic-backups-state"
      "/var/lib/sops-nix"
      "/var/log"
      "/var/lib/libvirt"
      "/var/lib/nixos"
      # Persist the whole dir (not just coredump) so systemd's
      # credential.secret survives reboots. Without it, anything created
      # via systemd-creds encrypt (libvirt's secrets-encryption-key, etc.)
      # becomes undecryptable after the next boot. Persisting as a file
      # via symlink doesn't work — systemd opens credential.secret with
      # O_NOFOLLOW and a symlink triggers ELOOP.
      "/var/lib/systemd"
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
      {
        directory = "/var/lib/grocy";
        user = "grocy";
        group = "nginx";
        mode = "0700";
      }
      {
        directory = "/var/lib/hermes";
        user = "hermes";
        group = "hermes";
        mode = "0700";
      }
      {
        directory = "/var/lib/postgresql";
        user = "postgres";
        group = "postgres";
        mode = "0700";
      }
    ];
    files = [
      "/etc/nix/netrc"
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
        ".local/share/zsh"
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
        ".claude"
        ".codex"
        ".crawl"
        ".config/obs-studio"
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
    };
  };
}
