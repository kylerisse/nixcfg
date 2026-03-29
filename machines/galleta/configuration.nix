{ config, pkgs, lib, network, ... }:
let
  inherit (network) domain prefix gateway subnet reverseZone
    forwardARecords cnameRecords reversePtrRecords dhcpReservations;
  lanIf = config.galleta.lanInterface;
  wanIf = config.galleta.wanInterface;
in
{
  options.galleta = {
    lanInterface = lib.mkOption { type = lib.types.str; default = "br0"; };
    wanInterface = lib.mkOption { type = lib.types.str; default = "enp1s0"; };
  };

  config = {

    boot.kernelPackages = pkgs.linuxPackages_latest;

    mynixcfg.users.kylerisse.enable = true;
    mynixcfg.nix-common.enable = true;
    mynixcfg.ssh-server.enable = true;
    mynixcfg.ssh-server.listenAddresses = [{ addr = gateway; port = 22; }];

    boot.kernel.sysctl = {
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
      "net.ipv6.conf.${wanIf}.accept_ra" = 2;
      "net.ipv6.conf.${wanIf}.autoconf" = true;
    };

    # NTP server for LAN
    services.chrony = {
      enable = true;
      extraConfig = ''
        allow ${subnet}
      '';
    };

    # DHCP server
    services.kea.dhcp4 = {
      enable = true;
      settings = {
        loggers = [{ name = "*"; severity = "INFO"; }];
        valid-lifetime = 86400;
        renew-timer = 21600;
        rebind-timer = 43200;
        interfaces-config.interfaces = [ lanIf ];
        lease-database = {
          type = "memfile";
          persist = true;
          name = "/var/lib/kea/dhcp4.leases";
        };
        option-data = [
          { name = "domain-name-servers"; data = gateway; }
          { name = "domain-name"; data = domain; }
          { name = "ntp-servers"; data = gateway; }
        ];
        subnet4 = [{
          subnet = subnet;
          id = 19216873;
          user-context.vlan = "home";
          pools = [
            { pool = "${prefix}.100 - ${prefix}.199"; }
          ];
          option-data = [
            { name = "routers"; data = gateway; }
          ];
          reservations-global = false;
          reservations-in-subnet = true;
          reservations = dhcpReservations;
        }];
      };
    };

    # DNS resolver + authoritative zones
    services.bind = {
      enable = true;
      cacheNetworks = [ subnet "127.0.0.1/32" "::1/128" ];
      forwarders = [ "1.0.0.1" "1.1.1.1" "2606:4700:4700::1111" "2606:4700:4700::1001" ];
      forward = "first";
      listenOn = [ gateway "127.0.0.1" ];
      listenOnIpv6 = [ "::1" ];
      zones = {
        "${domain}" = {
          master = true;
          masters = [ gateway ];
          file = pkgs.writeText "named.${domain}" ''
            $TTL 1D
            @ IN SOA galleta.${domain}. admin.${domain}. (
              6007
              1D
              1H
              1W
              3H
            )
            @  IN  NS  galleta.${domain}.
            ${forwardARecords}
            ${cnameRecords}
          '';
        };
        "${reverseZone}" = {
          master = true;
          masters = [ gateway ];
          file = pkgs.writeText "named.${prefix}" ''
            $TTL 86400
            @ IN SOA galleta.${domain}. admin.${domain}. (
              6007
              1D
              1H
              1W
              3H
            )
            @  IN  NS  galleta.${domain}.
            ${reversePtrRecords}
          '';
        };
      };
    };

    networking = {
      hostName = "galleta";
      bridges.br0 = {
        interfaces = [ "enp2s0" "enp3s0" "enp4s0" ];
        rstp = true;
      };
      interfaces = {
        enp1s0.useDHCP = true;
        br0.ipv4.addresses = [{
          address = "192.168.73.1";
          prefixLength = 24;
        }];
      };
      firewall.enable = false;
      nftables = {
        enable = true;
        ruleset = ''
          table inet filter {
            chain input {
              type filter hook input priority filter; policy drop;

              iifname "lo" accept

              ct state invalid drop
              ct state established,related accept

              iifname "${lanIf}" meta l4proto { icmp, ipv6-icmp } limit rate 25/second accept

              iifname "${lanIf}" tcp dport { 22, 53 } accept
              iifname "${lanIf}" udp dport { 53, 67, 123 } accept
            }

            chain forward {
              type filter hook forward priority filter; policy drop;

              ct state invalid drop
              ct state established,related accept

              iifname "${lanIf}" accept
            }

            chain output {
              type filter hook output priority filter; policy accept;
            }
          }

          table ip nat {
            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;
              oifname "${wanIf}" masquerade
            }
          }
        '';
      };
    };

    time.timeZone = "America/Los_Angeles";

    system.stateVersion = "25.11";
  };
}
