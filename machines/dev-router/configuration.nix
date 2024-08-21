{ config, pkgs, self, ... }:
let
  zoneSerial = "${toString self.lastModified}";
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  nix.settings = {
    trusted-users = [ "@wheel" ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  ssh-server.enable = true;
  #ssh-server.listenAddresses = [
  #  {
  #    addr = "192.168.70.1";
  #    port = 2222;
  #  }
  #  {
  #    addr = "192.168.73.31";
  #    port = 22;
  #  }
  #  {
  #    addr = "127.0.0.1";
  #    port = 22;
  #  }
  #];

  dualhome-nat.enable = true;
  dualhome-nat.internalInterface = "enp2s0";
  dualhome-nat.externalInterface = "enp1s0";
  dualhome-nat.internalCIDR = "192.168.70.0/24";

  dhcp-server.enable = true;
  dhcp-server.interfaces = [ "enp2s0" ];
  dhcp-server.dns = "192.168.70.1";
  dhcp-server.domain = "risse.tv";
  dhcp-server.reservations = [
    { hostname = "temp"; hw-address = "52:54:00:59:ca:fb"; ip-address = "192.168.70.92"; }
  ];
  dhcp-server.v4subnets = [{
    subnet = "192.168.70.0/24";
    id = 19216870;
    user-context.vlan = "kvm-unrouted";
    pools = [
      { pool = "192.168.70.100 - 192.168.70.199"; }
    ];
    option-data = [
      { name = "routers"; data = "192.168.70.1"; }
    ];
  }];

  dns-server.enable = true;
  dns-server.listenOn = [ "192.168.70.1" "127.0.0.1" ];
  dns-server.allowedCIDRs = [ "192.168.70.0/24" "127.0.0.1/32" "::1/128" ];
  dns-server.forwarders = [ "192.168.73.1" ];
  dns-server.zones =
    {
      "lab.risse.tv" = {
        master = true;
        masters = [ "192.168.70.1" ];
        file = pkgs.writeText "named.lab.risse.tv" ''
          $TTL 86400
          @ IN SOA dev-router.lab.risse.tv. admin.lab.risse.tv. (
            ${zoneSerial}
            1D
            1H
            1W
            3H
          )
          @                   IN    NS      dev-router.lab.risse.tv.
          dev-router          IN    A       192.168.70.1
          temp                IN    A       192.168.70.92
          nixos-sandbox       IN    A       143.198.136.198
        '';
      };
      "70.168.192.in-addr.arpa" = {
        master = true;
        masters = [ "192.168.70.1" ];
        file = pkgs.writeText "named.192.168.70" ''
          $TTL 86400
          @ IN SOA dev-router.lab.risse.tv. admin.lab.risse.tv (
            ${zoneSerial}
            1D
            1H
            1W
            3H
          )
          @                    IN   NS      dev.router.lab.risse.tv.
          1                    IN   PTR     dev-router.lab.risse.tv.
          92                   IN   PTR     temp.lab.risse.tv.
        '';
      };
    };

  networking = {
    hostName = "dev-router";
    interfaces = {
      enp1s0.useDHCP = true;
      enp2s0.ipv4.addresses = [{
        address = "192.168.70.1";
        prefixLength = 24;
      }];
    };
  };

  time.timeZone = "America/Los_Angeles";

  system.stateVersion = "24.05";
}
