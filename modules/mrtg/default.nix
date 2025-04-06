{ config, pkgs, lib, ... }:
let
  cfg = config.mrtg;
  inherit (lib) concatStringsSep types;
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.options) mkEnableOption mkOption;
in
{
  options.mrtg = {
    enable = mkEnableOption "MRTG";
    hostList = mkOption {
      type = types.listOf types.str;
    };
    # must be in /var/lib/ for systemd dynamic user to function
    statePath = mkOption {
      type = types.str;
      default = "/var/lib/mrtg";
      description = "state path where html and configs will be generated";
    };
    secretsPath = mkOption {
      type = types.str;
      default = "/etc/mrtg";
      description = "path where per host SNMP community files reside (ex: ''$''{secretsPath}/host.snmp)";
    };
    nginxEnable = mkEnableOption "enable nginx";
    nginxVhosts = mkOption {
      type = types.listOf types.str;
      default = [ "mrtg.example.com" ];
    };
    user = mkOption {
      type = types.str;
      default = "mrtg";
    };
    group = mkOption {
      type = types.str;
      default = "mrtg";
    };
  };
  config =
    let
      script = pkgs.writeShellScript "mrtg-generator" ''
        set -eo pipefail
        mkdir -p ${cfg.statePath}/configs/
        mkdir -p ${cfg.statePath}/html/
        for hostname in ${concatStringsSep " " cfg.hostList}; do
          echo "''${hostname}"
          mkdir -p ${cfg.statePath}/logs/''${hostname}
          snmp_file="${cfg.secretsPath}/''${hostname}.snmp"
          while [ ! -f ''${snmp_file} ]; do
            echo waiting for ''${snmp_file}
            sleep 10
          done
          echo "''${snmp_file} found! creating config..."
          snmp_community=''$(cat ''${snmp_file} | tr -d '\n')
          config_path="${cfg.statePath}/configs/''${hostname}.cfg"
          mkdir -p ${cfg.statePath}/html/''${hostname}
          ${pkgs.mrtg}/bin/cfgmaker \
          --no-down \
          --show-op-down \
          --output="''${config_path}" \
          --global="HtmlDir: ${cfg.statePath}/html/''${hostname}" \
          --global="ImageDir: ${cfg.statePath}/html/''${hostname}" \
          --global="LogDir: ${cfg.statePath}/logs/''${hostname}" \
          --global="options[_]: growright,bits" \
          --global="Refresh: 300" \
          ''${snmp_community}@''${hostname}
          echo "configuration created at ''${config_path}"
          index_path="${cfg.statePath}/html/''${hostname}/index.html"
          echo "Generating index html at ''${index_path}"
          ${pkgs.mrtg}/bin/indexmaker --output="''${index_path}" ''${config_path}
          sed -E -i 's/(mrtg-(l|m|r))\.gif/\1.png/g' ''${index_path}
        done
      '';
    in
    mkIf cfg.enable (
      lib.mkMerge [
        {
          systemd.services = builtins.listToAttrs (
            map
              (name: {
                name = "mrtg-${name}";
                value = {
                  after = [ "mrtg-generator.service" ];
                  environment.LANG = "C";
                  serviceConfig = {
                    ExecStart = "${pkgs.mrtg}/bin/mrtg ${cfg.statePath}/configs/${name}.cfg";
                    Type = "simple";
                    User = "${cfg.user}";
                    Group = "${cfg.group}";
                  };
                };
              })
              cfg.hostList
          );
          systemd.timers = builtins.listToAttrs (
            map
              (name: {
                name = "mrtg-${name}";
                value = {
                  wantedBy = [ "timers.target" ];
                  timerConfig = {
                    OnBootSec = "10";
                    OnUnitActiveSec = "300";
                    Unit = "mrtg-${name}.service";
                  };
                };
              })
              cfg.hostList
          );
        }
        {
          systemd.services.mrtg-generator = {
            description = "mrtg generator";
            after = [ "network.target" ];
            wantedBy = [ "multi-user.target" ];
            environment.LANG = "C";
            serviceConfig = {
              ExecStart = "${script}";
              Type = "simple";
              User = "${cfg.user}";
              Group = "${cfg.group}";
            };
          };
          systemd.tmpfiles.rules = [
            "d ${cfg.statePath} 0755 ${cfg.user} ${cfg.group}"
            "d ${cfg.secretsPath} 0550 ${cfg.user} ${cfg.group}"
          ];
        }
        {
          users = {
            users."${cfg.user}" = {
              isNormalUser = true;
              group = "${cfg.group}";
            };
            groups.${cfg.group} = { };
          };
        }
        {
          services.nginx = mkIf cfg.nginxEnable {
            enable = true;
            virtualHosts = lib.foldl'
              (acc: fqdn: acc // {
                "${fqdn}" = {
                  root = "${cfg.statePath}/html";
                  default = false;
                  enableACME = false;
                  locations."/" = {
                    extraConfig = ''
                      autoindex on;
                      autoindex_exact_size off;
                      autoindex_localtime on;
                    '';
                  };
                };
              })
              { }
              cfg.nginxVhosts;
          };
        }
      ]
    );
}
