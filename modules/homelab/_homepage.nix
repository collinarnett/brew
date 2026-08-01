{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    optional
    filter
    any
    attrValues
    ;
  cfg = config.brew.homelab;

  mediaGroup =
    optional cfg.jellyfin.enable {
      Jellyfin = {
        href = "https://media.${cfg.domain}";
        icon = "jellyfin.png";
        description = "Movies, TV, and music";
        # Jellyfin fixes its own listener at 8096 and the module exposes
        # no option for it.
        siteMonitor = "http://127.0.0.1:8096";
      };
    }
    ++ optional cfg.kavita.enable {
      Kavita = {
        href = "https://books.${cfg.domain}";
        icon = "kavita.png";
        description = "Ebook library and reader";
        siteMonitor = "http://${config.services.kavita.settings.IpAddresses}:${toString config.services.kavita.settings.Port}";
      };
    }
    ++ optional cfg.rqbit.enable {
      rqbit = {
        href = "https://torrents.${cfg.domain}/web/";
        icon = "mdi-download";
        description = "Torrent client";
        siteMonitor = "http://${config.services.rqbit.httpHost}:${toString config.services.rqbit.httpPort}";
      };
    };

  homeGroup = optional cfg.grocy.enable {
    Grocy = {
      href = "https://grocy.${cfg.domain}";
      icon = "grocy.png";
      description = "Groceries and household";
      siteMonitor = "https://grocy.${cfg.domain}";
    };
  };

  toolsGroup =
    optional cfg.searx.enable {
      SearXNG = {
        href = "https://search.${cfg.domain}";
        icon = "searxng.png";
        description = "Metasearch";
        siteMonitor = "http://${config.services.searx.settings.server.bind_address}:${toString config.services.searx.settings.server.port}";
      };
    }
    ++ optional cfg.radicle.enable {
      Radicle = {
        href = "https://garden.${cfg.domain}";
        icon = "mdi-source-branch";
        description = "Code forge";
        # The explorer is a static bundle nginx serves directly, so
        # watching radicle-httpd is what reveals whether repositories
        # actually resolve.
        siteMonitor = "http://${config.services.radicle.httpd.listenAddress}:${toString config.services.radicle.httpd.listenPort}";
      };
    }
    ++ optional cfg.kanidm.enable {
      Kanidm = {
        href = "https://idm.${cfg.domain}";
        icon = "kanidm.png";
        description = "Single sign-on";
        siteMonitor = "https://idm.${cfg.domain}";
      };
    };

  # apcupsd answers status queries on its network information server,
  # whose port the module leaves to apcupsd's own 3551 default since it
  # exposes nothing but a raw config blob. The daemon has no web
  # interface, so the tile carries no link.
  systemGroup = optional config.brew.apcupsd.enable {
    UPS = {
      description = "Battery backup";
      icon = "mdi-battery-charging";
      widget = {
        type = "apcups";
        url = "tcp://127.0.0.1:3551";
      };
    };
  };

  # CrowdSec has no self-hosted web UI; the widget shows live alert and
  # ban counts from the local API, and the link goes to the hosted
  # console (which stays a login page unless the engine is enrolled).
  securityGroup = optional cfg.crowdsec.enable {
    CrowdSec = {
      href = "https://app.crowdsec.net";
      icon = "crowdsec.png";
      description = "Intrusion detection";
      siteMonitor = "http://${config.services.crowdsec.settings.general.api.server.listen_uri}/health";
      widget = {
        type = "crowdsec";
        url = "http://${config.services.crowdsec.settings.general.api.server.listen_uri}";
        username = "{{HOMEPAGE_VAR_CROWDSEC_LOGIN}}";
        password = "{{HOMEPAGE_VAR_CROWDSEC_PASSWORD}}";
      };
    };
  };
in
{
  config = mkIf (cfg.enable && cfg.homepage.enable) {
    services.nginx.virtualHosts."home.${cfg.domain}" = {
      enableACME = true;
      # DNS-01 through the acme defaults; HTTP-01 cannot reach this host.
      acmeRoot = null;
      forceSSL = true;
      # Homepage binds every interface and its module offers no option to
      # narrow that, so the reverse proxy dials loopback to keep the
      # traffic on this machine.
      locations."/".proxyPass =
        "http://127.0.0.1:${toString config.services.homepage-dashboard.listenPort}";
    };

    services.homepage-dashboard = {
      enable = true;
      listenPort = 8082;
      allowedHosts = "home.${cfg.domain}";

      settings = {
        title = cfg.domain;
        theme = "dark";
        # The Dracula custom CSS overrides the variables of the gray preset.
        color = "gray";
        headerStyle = "clean";
        hideVersion = true;
        statusStyle = "dot";
      };

      widgets = [
        {
          resources = {
            cpu = true;
            memory = true;
            disk = [ "/persist" ];
            uptime = true;
          };
        }
      ]
      ++ optional cfg.searx.enable {
        search = {
          provider = "custom";
          url = "https://search.${cfg.domain}/search?q=";
          suggestionUrl = "https://search.${cfg.domain}/autocompleter?q=";
          showSearchSuggestions = true;
          target = "_self";
        };
      };

      services = filter (group: any (entries: entries != [ ]) (attrValues group)) [
        { Media = mediaGroup; }
        { Home = homeGroup; }
        { Tools = toolsGroup; }
        { Security = securityGroup; }
        { System = systemGroup; }
      ];

      customCSS = builtins.readFile ./homepage-dracula.css;

      environmentFiles = optional cfg.crowdsec.enable "/run/homepage-crowdsec.env";
    };

    # The crowdsec widget authenticates against the local API with the
    # machine credentials cscli writes to lapi.yaml at first start.
    # Homepage only reads secrets through {{HOMEPAGE_VAR_*}} environment
    # substitution, so translate the yaml into an environment file
    # before homepage starts.
    # Pulled in by homepage as a weak dependency: a missing or malformed
    # credentials file leaves this unit failed and visible in
    # `systemctl --failed` while the rest of the dashboard still starts.
    systemd.services.homepage-crowdsec-credentials = mkIf cfg.crowdsec.enable {
      description = "Derive homepage crowdsec widget credentials from lapi.yaml";
      after = [ "crowdsec.service" ];
      before = [ "homepage-dashboard.service" ];
      wantedBy = [ "homepage-dashboard.service" ];
      serviceConfig.Type = "oneshot";
      path = [ pkgs.gnused ];
      script = ''
        set -euo pipefail
        umask 077
        credentials=/var/lib/crowdsec/lapi.yaml
        login=$(sed -n 's/^login: //p' "$credentials")
        password=$(sed -n 's/^password: //p' "$credentials")
        if [ -z "$login" ] || [ -z "$password" ]; then
          echo "no machine credentials found in $credentials" >&2
          exit 1
        fi
        printf 'HOMEPAGE_VAR_CROWDSEC_LOGIN=%s\nHOMEPAGE_VAR_CROWDSEC_PASSWORD=%s\n' \
          "$login" "$password" > /run/homepage-crowdsec.env
      '';
    };
  };
}
