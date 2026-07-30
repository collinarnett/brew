{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.brew.homelab;
in
{
  config = mkIf (cfg.enable && cfg.kavita.enable) {
    clan.core.vars.generators.kavita_token_key = {
      files.kavita_token_key.owner = "kavita";
      runtimeInputs = [ pkgs.coreutils ];
      # Kavita requires a JWT signing key of at least 512 bits.
      script = ''
        head -c 64 /dev/urandom | base64 --wrap=0 > "$out"/kavita_token_key
      '';
    };

    services.kavita = {
      enable = true;
      tokenKeyFile = config.clan.core.vars.generators.kavita_token_key.files.kavita_token_key.path;
      settings = {
        IpAddresses = "127.0.0.1";
        # 5000 is taken by the docker registry.
        Port = 5001;
      };
    };
    users.users.kavita.extraGroups = [ "multimedia" ];
  };
}
