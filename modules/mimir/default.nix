{ config
, lib
, ...
}:
let
  cfg = config.mynixcfg.mimir;
in
{
  options.mynixcfg.mimir = {
    enable = lib.mkEnableOption "Mimir time series database";

    httpListenPort = lib.mkOption {
      type = lib.types.int;
      default = 3200;
    };

    grpcListenPort = lib.mkOption {
      type = lib.types.int;
      default = 9096;
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/mimir";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.mimir = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    services.mimir = {
      enable = true;
      configuration = {
        multitenancy_enabled = false;
        server = {
          http_listen_port = cfg.httpListenPort;
          grpc_listen_port = cfg.grpcListenPort;
        };
        common.storage = {
          backend = "filesystem";
          filesystem.dir = "${cfg.dataDir}/data";
        };
        blocks_storage = {
          storage_prefix = "blocks";
          tsdb.dir = "${cfg.dataDir}/tsdb";
        };
        compactor = {
          data_dir = "${cfg.dataDir}/compactor";
          compaction_interval = "30m";
        };
        ingester.ring = {
          replication_factor = 1;
          kvstore.store = "inmemory";
        };
      };
    };
  };
}
