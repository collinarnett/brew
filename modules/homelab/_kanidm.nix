{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.brew.homelab;
  vars = config.clan.core.vars.generators;
  acmeDir = config.security.acme.certs."idm.trexd.dev".directory;
in
{
  config = mkIf (cfg.enable && cfg.kanidm.enable) {
    clan.core.vars.generators.kanidm_admin_password = {
      files.kanidm_admin_password.owner = "kanidm";
      runtimeInputs = [ pkgs.coreutils ];
      script = ''
        head -c 32 /dev/urandom | base64 --wrap=0 | tr -d '+/=' > "$out"/kanidm_admin_password
      '';
    };

    clan.core.vars.generators.kanidm_idm_admin_password = {
      files.kanidm_idm_admin_password.owner = "kanidm";
      runtimeInputs = [ pkgs.coreutils ];
      script = ''
        head -c 32 /dev/urandom | base64 --wrap=0 | tr -d '+/=' > "$out"/kanidm_idm_admin_password
      '';
    };

    # Provisioning runs inside kanidm.service as the kanidm user, so it
    # needs direct read access to the client secret Kavita already uses.
    clan.core.vars.generators.kavita_oidc_client_secret.files.kavita_oidc_client_secret.owner =
      mkIf cfg.kavita.enable "kanidm";

    clan.core.vars.generators.jellyfin_oidc_client_secret = mkIf cfg.jellyfin.enable {
      files.jellyfin_oidc_client_secret.owner = "kanidm";
      runtimeInputs = [ pkgs.coreutils ];
      script = ''
        head -c 48 /dev/urandom | base64 --wrap=0 | tr -d '+/=' > "$out"/jellyfin_oidc_client_secret
      '';
    };

    # Kanidm terminates its own TLS even behind the reverse proxy, so it
    # gets a real certificate through the same route53 DNS challenge
    # Traefik uses, sharing the aws credentials var via the aws group.
    security.acme = {
      acceptTerms = true;
      certs."idm.trexd.dev" = {
        email = "collin@arnett.it";
        dnsProvider = "route53";
        group = "kanidm";
        environmentFile = pkgs.writeText "kanidm-acme-env" ''
          AWS_SHARED_CREDENTIALS_FILE=${vars.awscli2-credentials.files.awscli2-credentials.path}
          AWS_PROFILE=default
          AWS_REGION=us-east-1
        '';
        reloadServices = [ "kanidm.service" ];
      };
    };
    users.users.acme.extraGroups = [ "aws" ];

    services.kanidm = {
      package = pkgs.kanidmWithSecretProvisioning_1_10;
      server.enable = true;
      server.settings = {
        origin = "https://idm.trexd.dev";
        domain = "idm.trexd.dev";
        # The pcie-passthrough VM forwards 8443 and 8444 on the host.
        bindaddress = "127.0.0.1:8445";
        tls_chain = "${acmeDir}/fullchain.pem";
        tls_key = "${acmeDir}/key.pem";
      };

      provision = {
        enable = true;
        adminPasswordFile = vars.kanidm_admin_password.files.kanidm_admin_password.path;
        idmAdminPasswordFile = vars.kanidm_idm_admin_password.files.kanidm_idm_admin_password.path;

        groups = {
          homelab_users = { };
          kavita_admin = { };
          jellyfin_admins = { };
          jellyfin_users = { };
        };

        persons.trexd = {
          displayName = "Trexd";
          mailAddresses = [ "collin@arnett.it" ];
          groups = [
            "homelab_users"
            "kavita_admin"
            "jellyfin_admins"
            "jellyfin_users"
          ];
        };

        systems.oauth2.kavita = mkIf cfg.kavita.enable {
          displayName = "Kavita";
          originUrl = "https://books.trexd.dev/signin-oidc";
          originLanding = "https://books.trexd.dev";
          basicSecretFile = vars.kavita_oidc_client_secret.files.kavita_oidc_client_secret.path;
          preferShortUsername = true;
          scopeMaps.homelab_users = [
            "openid"
            "profile"
            "email"
            "offline_access"
          ];
          # Kavita reads roles from the "groups" claim with prefix "kavita-".
          claimMaps.groups = {
            joinType = "array";
            valuesByGroup.kavita_admin = [ "kavita-Admin" ];
          };
        };

        systems.oauth2.jellyfin = mkIf cfg.jellyfin.enable {
          displayName = "Jellyfin";
          originUrl = "https://media.trexd.dev/sso/OID/redirect/kanidm";
          originLanding = "https://media.trexd.dev";
          basicSecretFile = vars.jellyfin_oidc_client_secret.files.jellyfin_oidc_client_secret.path;
          preferShortUsername = true;
          # jellyfin-plugin-sso supports neither PKCE nor ES256 tokens.
          allowInsecureClientDisablePkce = true;
          enableLegacyCrypto = true;
          scopeMaps.homelab_users = [
            "openid"
            "profile"
            "email"
          ];
          # The claim values match the group names the SSO plugin was
          # configured with under the previous identity provider.
          claimMaps.groups = {
            joinType = "array";
            valuesByGroup = {
              jellyfin_admins = [ "jellyfin-admins" ];
              jellyfin_users = [ "jellyfin-users" ];
            };
          };
        };

        systems.oauth2.forward-auth = {
          displayName = "Forward Auth";
          originUrl = [
            "https://search.trexd.dev/oauth2/callback"
            "https://grocy.trexd.dev/oauth2/callback"
            "https://torrents.trexd.dev/oauth2/callback"
            "https://home.trexd.dev/oauth2/callback"
          ];
          originLanding = "https://home.trexd.dev";
          basicSecretFile = vars.oauth2_proxy.files.oauth2_proxy_client_secret.path;
          preferShortUsername = true;
          scopeMaps.homelab_users = [
            "openid"
            "profile"
            "email"
          ];
        };
      };
    };

    # The certificate must exist before kanidm can start.
    systemd.services.kanidm = {
      after = [ "acme-finished-idm.trexd.dev.target" ];
      wants = [ "acme-finished-idm.trexd.dev.target" ];
    };
  };
}
