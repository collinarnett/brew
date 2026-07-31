{
  config,
  lib,
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
      ];

      customCSS = builtins.readFile ./homepage-dracula.css;
    };
  };
}
