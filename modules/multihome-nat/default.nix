{ config, pkgs, inputs, lib, ... }:
{
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
            # TODO: how can i read the variables from the host config?
            # "net.ipv6.conf.${externalInterface}.accept_ra" = 2;
            # "net.ipv6.conf.${externalInterface}.autoconf" = true;
        };
    };
    networking = {
        enableIPv6 = true;
        nat = {
            enable = true;
            # inherit externalInterface;
            # internalInterfaces = [ internalInterface ];
            # internalIPs = [ "${internalCIDR}" ];
        };
        firewall.allowPing = false;
    };
}
