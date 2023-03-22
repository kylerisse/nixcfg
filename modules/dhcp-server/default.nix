{ config, pkgs, inputs, lib, ... }:
let
  format = pkgs.formats.json { };
  cfg = config.dhcp-server;
in
{
  options.dhcp-server = {
    interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "eth0" ];
      description = "DHCP listen interface";
    };
    dns = lib.mkOption {
      type = lib.types.str;
      default = "1.1.1.1,8.8.8.8";
      description = "List of DNS servers";
    };
    domain = lib.mkOption {
      type = lib.types.str;
      default = "example.com";
      description = "Domain name";
    };
    reservations = lib.mkOption {
      type = format.type;
      default = [
        {
          hostname = "example1";
          hw-address = "ab:cd:ef:12:34:56";
          ip-address = "192.168.0.5";
        }
        {
          hostname = "example2";
          hw-address = "90:ef:12:34:56:78";
          ip-address = "192.168.0.6";
        }
      ];
    };
    v4subnets = lib.mkOption {
      type = format.type;
      default = [{
        subnet = "192.168.0.0/24";
        id = 12345;
        user-context = {
          vlan = "default";
        };
        pools = [{
          pool = "192.168.0.10 - 192.168.0.254";
        }];
        option-data = [{
          name = "routers";
          data = "192.168.0.1";
        }];
      }];
      description = "ipv4 subnet config";
    };
  };
  config = {
    environment.systemPackages = with pkgs; [
      kea
    ];
    services.kea.dhcp4 = {
      enable = true;
      settings = {
        loggers = [{
          name = "*";
          severity = "DEBUG";
        }];
        valid-lifetime = 86400;
        renew-timer = 21600;
        rebind-timer = 43200;
        interfaces-config = {
          interfaces = cfg.interfaces;
        };
        lease-database = {
          type = "memfile";
          persist = true;
          name = "/var/lib/kea/dhcp4.leases";
        };
        option-data = [
          {
            name = "domain-name-servers";
            data = cfg.dns;
          }
          {
            name = "domain-name";
            data = cfg.domain;
          }
        ];
        reservation-mode = "global";
        reservations = cfg.reservations;
        subnet4 = cfg.v4subnets;
      };
    };
  };
}
