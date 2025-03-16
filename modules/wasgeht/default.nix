{ config
, pkgs
, lib
, ...
}:
let
  cfg = config.wasgeht;
in
{
  options.wasgeht = {
    enable = lib.mkEnableOption "wasgeht monitoring service";
    package = lib.mkPackageOption pkgs "wasgeht" { };

    group = lib.mkOption {
      type = lib.types.str;
      default = "wasgehtd";
    };

    hostFile = lib.mkOption {
      type = lib.types.str;
      default = builtins.toFile "default.json" ''
        {
          "localhost": {},
          "localhostv6": {
            "address": "::1"
          }
        }
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "info";
    };

    nginxEnable = lib.mkEnableOption "enable Nginx";

    nginxVhosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "wasgeht.example.com" ];
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 1982;
    };

    statePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/wasgeht";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "wasgehtd";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      services.wasgeht = {
        description = "wasgeht monitoring service";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "${cfg.user}";
          Group = "${cfg.group}";
          ExecStart = "${lib.getExe cfg.package} --data-dir=${cfg.statePath} --host-file=${cfg.hostFile} --port=${builtins.toString cfg.port} --log-level=${cfg.logLevel}";
          ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR1 $MAINPID";
        };
      };
      tmpfiles.rules = [
        "d ${cfg.statePath} 0755 ${cfg.user} ${cfg.group}"
      ];
    };
    users = {
      users."${cfg.user}" = {
        isNormalUser = true;
        group = "${cfg.group}";
      };
      groups."${cfg.group}" = { };
    };
    services.nginx = lib.mkIf cfg.nginxEnable {
      enable = true;
      virtualHosts = lib.foldl'
        (acc: fqdn: acc // {
          "${fqdn}" = {
            default = false;
            enableACME = false;
            locations."/" = {
              proxyPass = "http://localhost:${builtins.toString cfg.port}/";
            };
          };
        })
        { }
        cfg.nginxVhosts;
    };
  };
}
