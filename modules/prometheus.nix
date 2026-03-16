{ ... }:
{
  flake.modules.nixos.prometheus =
    { config, lib, ... }:
    let
      cfg = config.brew.prometheus;
    in
    {
      options.brew.prometheus.enable = lib.mkEnableOption "prometheus";
      config = lib.mkIf cfg.enable {
        services.prometheus = {
          enable = true;
          exporters = {
            node = {
              enable = true;
              enabledCollectors = [ "textfile" ];
              extraFlags = [ "--collector.textfile.directory=/var/lib/prometheus/node-exporter" ];
            };
            dcgm = {
              enable = true;
              collectInterval = 1000;
            };
          };

          scrapeConfigs = [
            {
              job_name = "node";
              static_configs = [
                {
                  targets = [
                    "localhost:${toString config.services.prometheus.exporters.node.port}"
                  ];
                }
              ];
            }
            {
              job_name = "dcgm";
              static_configs = [
                {
                  targets = [
                    "localhost:${toString config.services.prometheus.exporters.dcgm.port}"
                  ];
                }
              ];
            }
          ];
        };

        systemd.tmpfiles.rules = [
          "d /var/lib/prometheus/node-exporter 0700 node-exporter node-exporter -"
        ];
      };
    };
}
