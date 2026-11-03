{ ... }:
{
  flake.modules.nixos.claude-connectors =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.brew.claude-connectors;
      domain = config.brew.homelab.domain;
      host = "mcp.${domain}";
      vars = config.clan.core.vars.generators;
      issuer = "https://idm.${domain}/oauth2/openid/${clientId}";
      clientId = "claude-mcp";
      # Anthropic's outbound range for connector traffic, published at
      # https://platform.claude.com/docs/en/api/ip-addresses
      anthropicEgress = "160.79.104.0/21";
      # The router forwards public IPv4 443 here. Only the connector, kanidm
      # and SparkyFitness vhosts listen on it, so nothing else on nginx is
      # reachable from the internet.
      publicPort = 8448;
      publicListen = [
        {
          addr = "0.0.0.0";
          port = publicPort;
          ssl = true;
        }
      ];
      meshListen = [
        {
          addr = "0.0.0.0";
          port = 443;
          ssl = true;
        }
        {
          addr = "[::]";
          port = 443;
          ssl = true;
        }
        {
          addr = "0.0.0.0";
          port = 80;
        }
        {
          addr = "[::]";
          port = 80;
        }
      ];
      bridgePort = 8097;
      authPort = 4181;
      # How long a connector stays signed in after it is approved in kanidm.
      sessionLifetime = 30 * 24 * 3600;
      # Connector URL path → mcp-proxy's named server.
      servers = {
        mail = "proton-mail";
        calendar = "proton-calendar";
        monica = "monica";
        signal = "signal";
        signal-send = "signal-send";
        walmart = "walmart";
        grocy = "grocy";
      };
      # nginx variable names allow no hyphen.
      challengeVariable = path: "claude_connector_challenge_${lib.replaceStrings [ "-" ] [ "_" ] path}";
      resourceUrl = path: "https://${host}/${path}/mcp";
      metadataUrl = path: "https://${host}/.well-known/oauth-protected-resource/${path}/mcp";
      # The bridge runs the same commands Claude Code does, read from the
      # user's MCP server definitions.
      userServers = config.home-manager.users.${config.brew.user}.programs.mcp.servers;
      bridgeConfig = (pkgs.formats.json { }).generate "mcp-proxy-servers.json" {
        mcpServers = lib.genAttrs (lib.attrValues servers) (
          name:
          {
            inherit (userServers.${name}) command;
          }
          // lib.optionalAttrs (userServers.${name}.args or null != null) {
            inherit (userServers.${name}) args;
          }
        );
      };
    in
    {
      options.brew.claude-connectors = {
        enable = lib.mkEnableOption "the homelab MCP servers (Proton mail and calendar, Monica, Signal, Walmart, Grocy) as claude.ai custom connectors";
        publicInterface = lib.mkOption {
          type = lib.types.str;
          example = "eno2";
          description = ''
            Interface the router forwards public IPv4 port 443 to, as port
            8448. Only Anthropic's connector range and the LAN may reach
            that port, or the ordinary web ports, through it.
          '';
        };
        lanSubnet = lib.mkOption {
          type = lib.types.str;
          example = "192.168.1.0/24";
          description = "IPv4 LAN that keeps reaching the web ports through the public interface.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = config.brew.homelab.enable && config.brew.homelab.kanidm.enable;
            message = "brew.claude-connectors authenticates through the homelab's kanidm.";
          }
        ];

        # Bridge and the MCP bridge run as user services, and the connectors
        # must answer whether or not anyone is logged in.
        users.users.${config.brew.user}.linger = true;

        services.kanidm.provision = {
          groups.mcp_users = { };
          persons.trexd.groups = [ "mcp_users" ];
          # A confidential client: claude.ai and the token check share its
          # secret, and kanidm still enforces PKCE.
          systems.oauth2.${clientId} = {
            displayName = "Claude connectors";
            basicSecretFile = vars.claude-connectors.files.client_secret.path;
            originUrl = "https://claude.ai/api/mcp/auth_callback";
            originLanding = "https://claude.ai";
            preferShortUsername = true;
            scopeMaps.mcp_users = [
              "openid"
              "offline_access"
            ];
          };
        };

        # Kanidm ends an OAuth2 session at whichever comes first: its refresh
        # token expiry, set per client, or the expiry of the kanidm login
        # that approved it, set by account policy on idm_all_accounts. Both
        # have to reach the connector lifetime, so every kanidm login lasts
        # that long too. The provisioner sets neither attribute, and kanidm
        # keeps them across restarts once set.
        systemd.services.kanidm-claude-connector-lifetime = {
          description = "Keep Claude connector sessions signed in to kanidm";
          wantedBy = [ "multi-user.target" ];
          after = [ "kanidm.service" ];
          requires = [ "kanidm.service" ];
          path = [ config.services.kanidm.package ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "kanidm";
            RuntimeDirectory = "kanidm-claude-connector-lifetime";
          };
          # The CLI keeps its login token under ~/.cache whatever cache path
          # it is given, and the kanidm user's home is not writable.
          environment.HOME = "/run/kanidm-claude-connector-lifetime";
          script =
            let
              provision = config.services.kanidm.provision;
              connection = lib.escapeShellArgs (
                [
                  "--url=${provision.instanceUrl}"
                  "--name=idm_admin"
                ]
                ++ lib.optional provision.acceptInvalidCerts "--accept-invalid-certs"
              );
            in
            ''
              KANIDM_PASSWORD=$(< ${provision.idmAdminPasswordFile}) kanidm login ${connection}
              kanidm system oauth2 set-refresh-token-expiry ${connection} ${clientId} ${toString sessionLifetime}
              kanidm group account-policy auth-expiry ${connection} idm_all_accounts ${toString sessionLifetime}
            '';
        };

        clan.core.vars.generators.claude-connectors = {
          # The kanidm provisioner reads the client secret to register it.
          # It is also entered once in claude.ai: clan vars get azathoth
          # claude-connectors/client_secret
          files.client_secret.owner = "kanidm";
          files.cookie_secret = { };
          runtimeInputs = [ pkgs.coreutils ];
          script = ''
            head -c 48 /dev/urandom | base64 --wrap=0 | tr -d '+/=' > "$out"/client_secret
            head -c 32 /dev/urandom | base64 --wrap=0 | tr -- '+/' '-_' > "$out"/cookie_secret
          '';
        };

        # Verifies kanidm-issued access tokens for this client and answers
        # 401 to anything else; it never runs a browser login itself.
        systemd.services.oauth2-proxy-claude-connectors = {
          description = "Bearer token check in front of the Claude connector MCP servers";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "kanidm.service"
          ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            DynamicUser = true;
            LoadCredential = [
              "client_secret:${vars.claude-connectors.files.client_secret.path}"
              "cookie_secret:${vars.claude-connectors.files.cookie_secret.path}"
            ];
            Restart = "on-failure";
            ExecStart = lib.escapeShellArgs [
              (lib.getExe pkgs.oauth2-proxy)
              "--http-address=127.0.0.1:${toString authPort}"
              "--reverse-proxy=true"
              "--trusted-proxy-ip=127.0.0.1/32"
              "--provider=oidc"
              "--oidc-issuer-url=${issuer}"
              "--client-id=${clientId}"
              "--client-secret-file=%d/client_secret"
              "--code-challenge-method=S256"
              "--skip-jwt-bearer-tokens=true"
              "--api-route=^/"
              "--email-domain=*"
              # Access tokens identify the person by subject, not email.
              "--oidc-email-claim=sub"
              "--cookie-secret-file=%d/cookie_secret"
              "--upstream=http://127.0.0.1:${toString bridgePort}/"
            ];
          };
        };

        services.nginx.appendHttpConfig = lib.concatStrings (
          lib.mapAttrsToList (path: _: ''
            map $status ${"$" + challengeVariable path} {
              401 'Bearer resource_metadata="${metadataUrl path}"';
              default "";
            }
          '') servers
        );

        # Any other name on the public port gets its TLS handshake refused,
        # so it cannot fall through to whichever vhost happens to be first.
        services.nginx.virtualHosts.claude-connectors-unknown = {
          serverName = "_";
          default = true;
          rejectSSL = true;
          listen = publicListen;
        };

        # kanidm must answer Anthropic too: Claude reads its OAuth metadata
        # and exchanges codes for tokens there.
        services.nginx.virtualHosts."idm.${domain}".listen = meshListen ++ publicListen;

        # SparkyFitness serves its own MCP endpoint and is the OAuth server
        # for it, both under its public origin, so Claude connects to
        # https://fitness.${domain}/mcp directly.
        services.nginx.virtualHosts."fitness.${domain}" =
          lib.mkIf config.brew.homelab.sparkyfitness.enable
            {
              listen = meshListen ++ publicListen;
            };

        services.nginx.virtualHosts.${host} = {
          enableACME = true;
          # The certificate comes through the route53 DNS challenge; nothing
          # answers HTTP-01 on this host.
          acmeRoot = null;
          onlySSL = true;
          listen = publicListen;
          extraConfig = ''
            allow ${anthropicEgress};
            allow ${cfg.lanSubnet};
            allow 127.0.0.1;
            allow ::1;
            deny all;
          '';
          locations = lib.mkMerge (
            lib.mapAttrsToList (path: server: {
              # RFC 9728 metadata: where Claude learns which authorization
              # server issues tokens for this resource.
              "= /.well-known/oauth-protected-resource/${path}/mcp".extraConfig = ''
                default_type application/json;
                return 200 '${
                  builtins.toJSON {
                    resource = resourceUrl path;
                    authorization_servers = [ issuer ];
                    scopes_supported = [
                      "openid"
                      "offline_access"
                    ];
                    bearer_methods_supported = [ "header" ];
                  }
                }';
              '';
              "/${path}/" = {
                proxyPass = "http://127.0.0.1:${toString authPort}/servers/${server}/";
                extraConfig = ''
                  proxy_hide_header WWW-Authenticate;
                  add_header WWW-Authenticate ${"$" + challengeVariable path} always;
                  proxy_buffering off;
                  proxy_read_timeout 300s;
                '';
              };
            }) servers
          );
        };

        # The public port admits Anthropic's range and the LAN. The ordinary
        # web ports serve the mesh and the LAN only, whatever the router
        # forwards.
        networking.firewall.extraCommands = ''
          iptables -I nixos-fw 1 -i ${cfg.publicInterface} -p tcp -m multiport --dports 80,443 -j nixos-fw-refuse
          iptables -I nixos-fw 1 -i ${cfg.publicInterface} -p tcp -m multiport --dports 80,443 -s ${cfg.lanSubnet} -j nixos-fw-accept
          iptables -I nixos-fw 1 -i ${cfg.publicInterface} -p tcp --dport ${toString publicPort} -s ${cfg.lanSubnet} -j nixos-fw-accept
          iptables -I nixos-fw 1 -i ${cfg.publicInterface} -p tcp --dport ${toString publicPort} -s ${anthropicEgress} -j nixos-fw-accept
        '';

        home-manager.users.${config.brew.user} = {
          systemd.user.services.claude-connectors-mcp-proxy = {
            Unit.Description = "Streamable HTTP bridge to the connector MCP servers";
            Install.WantedBy = [ "default.target" ];
            Service = {
              ExecStart = lib.escapeShellArgs [
                (lib.getExe pkgs.mcp-proxy)
                "--host=127.0.0.1"
                "--port=${toString bridgePort}"
                "--named-server-config=${bridgeConfig}"
              ];
              Restart = "on-failure";
            };
          };
        };
      };
    };
}
