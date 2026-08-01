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
  acmeDir = config.security.acme.certs."idm.${cfg.domain}".directory;
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
    # needs direct read access to the client secret shared with Kavita.
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
    # gets a real certificate through the route53 DNS challenge, sharing
    # the acme credentials var with the other certs.
    security.acme = {
      acceptTerms = true;
      certs."idm.${cfg.domain}" = {
        email = "collin@arnett.it";
        dnsProvider = "route53";
        group = "kanidm";
        environmentFile = pkgs.writeText "kanidm-acme-env" ''
          AWS_SHARED_CREDENTIALS_FILE=${vars.acme-aws-credentials.files.acme-aws-credentials.path}
          AWS_PROFILE=default
          AWS_REGION=us-east-1
        '';
        reloadServices = [ "kanidm.service" ];
      };
    };
    users.users.nginx.extraGroups = [ "kanidm" ];

    services.kanidm = {
      package = pkgs.kanidmWithSecretProvisioning_1_10;
      server.enable = true;
      server.settings = {
        origin = "https://idm.${cfg.domain}";
        domain = "idm.${cfg.domain}";
        # The pcie-passthrough VM forwards 8443 and 8444 on the host.
        bindaddress = "127.0.0.1:8445";
        tls_chain = "${acmeDir}/fullchain.pem";
        tls_key = "${acmeDir}/key.pem";
        # Trust X-Forwarded-For from nginx so rate limiting and audit
        # logs see real client addresses instead of 127.0.0.1.
        http_client_address_info.x-forward-for = [ "127.0.0.1" ];
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
          originUrl = "https://books.${cfg.domain}/signin-oidc";
          originLanding = "https://books.${cfg.domain}";
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
          originUrl = "https://media.${cfg.domain}/sso/OID/redirect/kanidm";
          originLanding = "https://media.${cfg.domain}";
          basicSecretFile = vars.jellyfin_oidc_client_secret.files.jellyfin_oidc_client_secret.path;
          preferShortUsername = true;
          # jellyfin-plugin-sso cannot validate ES256 tokens; legacy RS256
          # crypto is required.
          enableLegacyCrypto = true;
          scopeMaps.homelab_users = [
            "openid"
            "profile"
            "email"
          ];
          # The claim values must match the AdminRoles and Roles strings
          # in the SSO plugin's configuration (SSO-Auth.xml).
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
          # The nginx integration routes every sign-in through the shared
          # auth domain, so this is the only redirect target.
          originUrl = "https://home.${cfg.domain}/oauth2/callback";
          originLanding = "https://home.${cfg.domain}";
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
      after = [ "acme-finished-idm.${cfg.domain}.target" ];
      wants = [ "acme-finished-idm.${cfg.domain}.target" ];
    };

    # Kanidm refuses plaintext HTTP, so nginx re-encrypts to the backend;
    # the SNI needs pinning since the dial address is 127.0.0.1 but the
    # backend cert is for the idm subdomain.
    services.nginx.virtualHosts."idm.${cfg.domain}" = {
      # Serve the same DNS-challenge certificate kanidm terminates with;
      # nginx joins the kanidm group to read it.
      useACMEHost = "idm.${cfg.domain}";
      forceSSL = true;
      locations."/" = {
        proxyPass = "https://${config.services.kanidm.server.settings.bindaddress}";
        extraConfig = ''
          proxy_ssl_server_name on;
          proxy_ssl_name idm.${cfg.domain};
        '';
      };
    };
  };
}
