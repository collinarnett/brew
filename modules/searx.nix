{config, ...}: {
  services.searx = {
    enable = true;
    settings = {
      server.port = 8080;
      server.secret_key = "@SEARX_SECRET_KEY@";
      ui.infinite_scroll = true;
      search = {
        autocomplete = "google";
        autocomplete_min = 3;
      };
    };
  };
  systemd.services.searx.environment = {
    SEARX_SECRET_KEY = "$(cat ${config.sops.secrets.searx_secret_key.path})";
  };
}
