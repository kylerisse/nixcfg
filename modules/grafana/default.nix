{ config
, lib
, ...
}:
let
  cfg = config.mynixcfg.grafana;
in
{
  options.mynixcfg.grafana = {
    enable = lib.mkEnableOption "Grafana dashboard";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "grafana.risse.tv";
    };

    httpPort = lib.mkOption {
      type = lib.types.int;
      default = 3000;
    };

    mimirUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:3200/prometheus";
    };

    tempoUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:4410";
    };

    secretKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to file containing the Grafana secret key";
    };
  };

  config = lib.mkIf cfg.enable {
    services.grafana = {
      enable = true;
      settings.security.secret_key = "$__file{${cfg.secretKeyFile}}";
      settings."plugin.tempo".enabled = true;
      settings.server = {
        domain = cfg.domain;
        http_addr = "127.0.0.1";
        http_port = cfg.httpPort;
        protocol = "http";
      };
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Mimir";
            type = "prometheus";
            uid = "PAE45454D0EDB9216";
            url = cfg.mimirUrl;
            isDefault = true;
          }
          {
            name = "Tempo";
            type = "tempo";
            uid = "tempo";
            url = cfg.tempoUrl;
            jsonData = {
              httpMethod = "GET";
            };
          }
        ];
        dashboards.settings.providers = [
          {
            name = "default";
            options.path = ./dashboards;
          }
        ];
      };
    };
  };
}
