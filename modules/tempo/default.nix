{ config
, lib
, ...
}:
let
  cfg = config.mynixcfg.tempo;
in
{
  options.mynixcfg.tempo = {
    enable = lib.mkEnableOption "Grafana Tempo distributed tracing backend";

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/tempo";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.tempo = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    services.tempo = {
      enable = true;
      settings = {
        server = {
          http_listen_port = 4410;
        };
        # avoid port 7946 conflict with mimir memberlist on same host
        memberlist.bind_port = 7947;
        distributor.receivers.otlp.protocols = {
          http.endpoint = "127.0.0.1:4418";
        };
        metrics_generator = {
          ring.instance_addr = "127.0.0.1";
          storage = {
            path = "${cfg.dataDir}/generator/wal";
            remote_write = [
              { url = "http://127.0.0.1:3200/api/v1/push"; }
            ];
          };
        };
        overrides.defaults.metrics_generator.processors = [ "service-graphs" "span-metrics" "local-blocks" ];
        storage.trace = {
          backend = "local";
          local.path = "${cfg.dataDir}/traces";
          wal.path = "${cfg.dataDir}/wal";
        };
      };
    };
  };
}
