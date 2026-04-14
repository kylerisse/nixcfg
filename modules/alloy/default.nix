{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.mynixcfg.alloy;

  scrapeTargetsList = lib.concatMapStringsSep ",\n    "
    (t:
      ''{"__address__" = "${t}"}''
    )
    cfg.scrapeTargets;

  scrapeTargetsBlock = lib.optionalString (cfg.scrapeTargets != [ ]) ''

    prometheus.scrape "additional_targets" {
      targets = [
        ${scrapeTargetsList},
      ]
      forward_to = [prometheus.remote_write.mimir.receiver]
      scrape_interval = "15s"
    }
  '';

  alloyConfig = pkgs.writeText "config.alloy" ''
    prometheus.exporter.unix "local" {
    }

    prometheus.scrape "local" {
      targets = prometheus.exporter.unix.local.targets
      forward_to = [prometheus.remote_write.mimir.receiver]
      scrape_interval = "15s"
    }

    prometheus.remote_write "mimir" {
      external_labels = {
        host = "${cfg.hostname}",
      }
      endpoint {
        url = "${cfg.remoteWriteUrl}"
      }
    }
    ${scrapeTargetsBlock}
  '';
in
{
  options.mynixcfg.alloy = {
    enable = lib.mkEnableOption "Grafana Alloy telemetry agent";

    hostname = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Hostname label attached to all pushed metrics";
    };

    remoteWriteUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://qube.risse.tv:3200/api/v1/push";
    };

    scrapeTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional host:port targets to scrape (e.g. ap1.risse.tv:9100)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.alloy = {
      enable = true;
      configPath = alloyConfig;
    };
  };
}
