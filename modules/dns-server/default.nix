{ config, pkgs, inputs, lib, ... }:
let
  format = pkgs.formats.json { };
  cfg = config.dns-server;
in
{
  options.dns-server = {
    enable = lib.mkEnableOption (lib.mdDoc "DNS Server");
    listenOn = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "192.168.0.1" ];
      description = "DNS listen interface";
    };
    allowedCIDRs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "CIDRs allowed to recursive query";
      default = [ "192.168.0.0/24" "127.0.0.1/32" ];
    };
    forwarders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "9.9.9.9" ];
      description = "DNS forwarders";
    };
    zones = lib.mkOption {
      type = format.type;
      default = {
        "example.com" = {
          master = true;
          masters = [ "192.168.0.1" "127.0.0.1" ];
          slaves = [ ];
          file = pkgs.writeText "named.example.com" ''
            $ORIGIN example.com.
            $TTL    86400
            @ IN SOA server.example.com. admin.example.com. (
            1                       ; serial number
            3600                    ; refresh
            900                     ; retry
            1209600                 ; expire
            1800                    ; minimum
            )
                            IN    NS      server.example.com.
            server          IN    A               192.168.0.1
            dns             IN    CNAME   server.example.com.
          '';
          extraConfig = "";
        };
      };
    };
  };
  config = {
    services.bind.enable = cfg.enable;
    services.bind.cacheNetworks = cfg.allowedCIDRs;
    services.bind.forwarders = cfg.forwarders;
    services.bind.forward = "first";
    services.bind.listenOn = cfg.listenOn;
    services.bind.zones = cfg.zones;
    networking.firewall.allowedTCPPorts = [ 53 ];
    networking.firewall.allowedUDPPorts = [ 53 ];
  };
}
