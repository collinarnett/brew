{ config, ...}:

{
  services.searx = {
    enable = true;
    settings = {
      use_default_settings = true;
      server = {
        secret_key = "@SEARX_SECRET_KEY@";
        bind_address = "0.0.0.0";
      };
    };
  };

  systemd.services.searx.environment.SEARX_SECRET_KEY = "$(cat ${config.sops.secrets.searx_secret_key.path})";
}

