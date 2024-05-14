{
  services.jellyfin.enable = true;
  users.groups.multimedia = {};
  users.users.jellyfin.extraGroups = ["multimedia"];
  systemd.tmpfiles.rules = [
    "d /media 0770 - multimedia - -"
  ];
}
