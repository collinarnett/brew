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
        href = "https://media.trexd.dev";
        icon = "jellyfin.png";
        description = "Movies, TV, and music";
        siteMonitor = "http://127.0.0.1:8096";
      };
    }
    ++ optional cfg.kavita.enable {
      Kavita = {
        href = "https://books.trexd.dev";
        icon = "kavita.png";
        description = "Ebook library and reader";
        siteMonitor = "http://127.0.0.1:5001";
      };
    }
    ++ optional cfg.rqbit.enable {
      rqbit = {
        href = "https://torrents.trexd.dev/web/";
        icon = "mdi-download";
        description = "Torrent client";
        siteMonitor = "http://127.0.0.1:3030";
      };
    };

  homeGroup = optional cfg.grocy.enable {
    Grocy = {
      href = "https://grocy.trexd.dev";
      icon = "grocy.png";
      description = "Groceries and household";
      siteMonitor = "https://grocy.trexd.dev";
    };
  };

  toolsGroup =
    optional cfg.searx.enable {
      SearXNG = {
        href = "https://search.trexd.dev";
        icon = "searxng.png";
        description = "Metasearch";
        siteMonitor = "http://127.0.0.1:8080";
      };
    }
    ++ optional cfg.radicle.enable {
      Radicle = {
        href = "https://garden.trexd.dev";
        icon = "mdi-source-branch";
        description = "Code forge";
        siteMonitor = "http://127.0.0.1:8779";
      };
    }
    ++ optional cfg.kanidm.enable {
      Kanidm = {
        href = "https://idm.trexd.dev";
        icon = "kanidm.png";
        description = "Single sign-on";
        siteMonitor = "https://idm.trexd.dev";
      };
    };

  # apcupsd answers status queries on its network information server.
  # The daemon has no web interface, so the tile carries no link.
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
      siteMonitor = "http://127.0.0.1:8081/health";
      widget = {
        type = "crowdsec";
        url = "http://127.0.0.1:8081";
        username = "{{HOMEPAGE_VAR_CROWDSEC_LOGIN}}";
        password = "{{HOMEPAGE_VAR_CROWDSEC_PASSWORD}}";
      };
    };
  };
in
{
  config = mkIf (cfg.enable && cfg.homepage.enable) {
    services.nginx.virtualHosts."home.trexd.dev" = {
      enableACME = true;
      # DNS-01 through the acme defaults; HTTP-01 cannot reach this host.
      acmeRoot = null;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:8082";
    };

    services.homepage-dashboard = {
      enable = true;
      listenPort = 8082;
      allowedHosts = "home.trexd.dev";

      settings = {
        title = "trexd.dev";
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
          url = "https://search.trexd.dev/search?q=";
          suggestionUrl = "https://search.trexd.dev/autocompleter?q=";
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
