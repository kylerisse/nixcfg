{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.mynixcfg.alloy;

  mkTargetsList = targets: lib.concatMapStringsSep ",\n      "
    (t: ''{"__address__" = "${t}"}'')
    targets;

  apScrapeBlock = lib.optionalString (cfg.apTargets != [ ]) ''

    discovery.relabel "aps" {
      targets = [
        ${mkTargetsList cfg.apTargets},
      ]

      rule {
        source_labels = ["__address__"]
        regex         = "([^.]+)\\..*"
        target_label  = "instance"
        replacement   = "$1"
      }
    }

    prometheus.scrape "aps" {
      targets    = discovery.relabel.aps.output
      job_name   = "aps"
      forward_to = [prometheus.remote_write.mimir.receiver]
      scrape_interval = "15s"
    }
  '';

  alloyConfig = pkgs.writeText "config.alloy" ''
    prometheus.exporter.unix "local" {
    }

    prometheus.scrape "local" {
      targets  = prometheus.exporter.unix.local.targets
      job_name = "integrations/unix"
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
    ${apScrapeBlock}
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
      default = "https://telemetry.risse.tv/mimir/api/v1/push";
    };

    apTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "AP host:port targets to scrape with job=aps";
    };
  };

  config = lib.mkIf cfg.enable {
    services.alloy = {
      enable = true;
      configPath = alloyConfig;
    };
  };
}
