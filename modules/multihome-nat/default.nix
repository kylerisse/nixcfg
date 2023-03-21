{ config, pkgs, inputs, lib, ... }:
let
    cfg = config.dualhome-nat;
in
{
    options.dualhome-nat = {
        externalInterface = lib.mkOption {
            type = lib.types.str;
            default = "eth0";
            description = "External Interface";
        };
        internalInterface = lib.mkOption {
            type = lib.types.str;
            default = "eth1";
            description = "Internal Interface";
        };
        internalCIDR = lib.mkOption {
            type = lib.types.str;
            default = "192.168.0.0/24";
            description = "CIDR of internal clients";
        };
    };

    config = {
        boot = {
            kernelModules = [
            "iptable_nat"
            "iptable_filter"
            "xt_nat"
            ];
            kernel.sysctl = {
                "net.ipv4.tcp_syncookies" = true;
                "net.ipv4.conf.all.forwarding" = true;
                "net.ipv4.conf.all.rp_filter" = true;
                "net.ipv4.conf.default.rp_filter" = true;
                "net.ipv4.conf.all.accept_redirects" = 0;
                "net.ipv4.conf.all.log_martians" = true;
                "net.ipv6.conf.all.forwarding" = true;
                "net.ipv6.conf.all.accept_ra" = 0;
                "net.ipv6.conf.all.autoconf" = 0;
                "net.ipv6.conf.all.use_tempaddr" = 0;
                "net.ipv6.conf.all.accept_redirects" = 0;
                "net.ipv6.conf.${cfg.externalInterface}.accept_ra" = 2;
                "net.ipv6.conf.${cfg.externalInterface}.autoconf" = true;
            };
        };
        networking = {
            enableIPv6 = true;
            nat = {
                enable = true;
                internalInterfaces = [ cfg.internalInterface ];
                internalIPs = [ "${cfg.internalCIDR}" ];
            };
            firewall.allowPing = false;
        };
    };
}
