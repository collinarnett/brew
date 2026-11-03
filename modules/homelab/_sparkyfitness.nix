{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.brew.homelab;
  host = "fitness.${cfg.domain}";
  sparky = config.services.sparkyfitness;
  vars = config.clan.core.vars.generators.sparkyfitness;
in
{
  config = mkIf (cfg.enable && cfg.sparkyfitness.enable) {
    assertions = [
      {
        assertion = cfg.kanidm.enable;
        message = "brew.homelab.sparkyfitness signs in through the homelab's kanidm.";
      }
    ];

    # The backend and its db-init service read every secret from one
    # EnvironmentFile. The OIDC client secret is also a file of its own,
    # which the kanidm provisioner reads to register the client.
    clan.core.vars.generators.sparkyfitness = {
      files.oidc_client_secret.owner = "kanidm";
      files.env = { };
      runtimeInputs = with pkgs; [
        coreutils
        openssl
      ];
      script = ''
        openssl rand -base64 48 | tr -d '+/=\n' > "$out"/oidc_client_secret
        {
          printf 'SPARKY_FITNESS_DB_PASSWORD=%s\n' "$(openssl rand -hex 32)"
          printf 'SPARKY_FITNESS_APP_DB_PASSWORD=%s\n' "$(openssl rand -hex 32)"
          printf 'SPARKY_FITNESS_API_ENCRYPTION_KEY=%s\n' "$(openssl rand -hex 32)"
          printf 'BETTER_AUTH_SECRET=%s\n' "$(openssl rand -base64 32)"
          printf 'SPARKY_FITNESS_OIDC_CLIENT_SECRET=%s\n' "$(cat "$out"/oidc_client_secret)"
        } > "$out"/env
      '';
    };

    services.sparkyfitness = {
      enable = true;
      frontendUrl = "https://${host}";
      environmentFile = vars.files.env.path;
      nginx.virtualHost = host;
      extraEnvironment = {
        SPARKY_FITNESS_OIDC_AUTH_ENABLED = "true";
        SPARKY_FITNESS_OIDC_PROVIDER_SLUG = "kanidm";
        SPARKY_FITNESS_OIDC_PROVIDER_NAME = "Kanidm";
        SPARKY_FITNESS_OIDC_ISSUER_URL = "https://idm.${cfg.domain}/oauth2/openid/sparkyfitness";
        SPARKY_FITNESS_OIDC_CLIENT_ID = "sparkyfitness";
        # Kanidm signs ID tokens with ES256 unless legacy crypto is enabled.
        SPARKY_FITNESS_OIDC_ID_TOKEN_SIGNED_ALG = "ES256";
        # Matched against the groups claim kanidm's claim map emits.
        SPARKY_FITNESS_OIDC_ADMIN_GROUP = "sparkyfitness-admins";
        SPARKY_FITNESS_OIDC_AUTO_REDIRECT = "true";
        SPARKY_FITNESS_DISABLE_EMAIL_LOGIN = "true";
      };
    };

    services.nginx.virtualHosts.${host} = {
      enableACME = true;
      # DNS-01 through the acme defaults; HTTP-01 cannot reach this host.
      acmeRoot = null;
      forceSSL = true;
      # OAuth discovery for remote MCP clients. Without this location the
      # SPA catch-all answers these paths with index.html.
      locations."^~ /.well-known/oauth-".proxyPass = "http://127.0.0.1:${toString sparky.port}";
    };

    # The remote MCP endpoint only accepts OAuth tokens once this admin
    # setting is on, and it lives in the database rather than the
    # environment. The backend creates the column in its startup
    # migrations, so this waits for it before setting it.
    systemd.services.sparkyfitness-mcp-oauth = {
      description = "Enable SparkyFitness remote MCP OAuth";
      wantedBy = [ "multi-user.target" ];
      after = [ "sparkyfitness.service" ];
      requires = [ "sparkyfitness.service" ];
      path = [ config.services.postgresql.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "postgres";
      };
      script = ''
        for _ in $(seq 60); do
          if [ "$(psql -d ${sparky.database.name} -tAc "SELECT 1 FROM information_schema.columns WHERE table_name = 'global_settings' AND column_name = 'mcp_oauth_enabled'")" = 1 ]; then
            psql -d ${sparky.database.name} -c "UPDATE global_settings SET mcp_oauth_enabled = true WHERE id = 1"
            exit 0
          fi
          sleep 1
        done
        echo "global_settings.mcp_oauth_enabled did not appear within 60 seconds" >&2
        exit 1
      '';
    };

    # Food logs and measurements cannot be recreated, so a nightly dump
    # lands in the backed-up tier ahead of the restic job that ships it.
    services.postgresqlBackup = {
      enable = true;
      databases = [ sparky.database.name ];
      startAt = "*-*-* 01:20:00";
    };
  };
}
