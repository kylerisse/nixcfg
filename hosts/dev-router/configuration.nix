{ config, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  _module.args = {
    nixinate = {
      host = "dev-router";
      buildOn = "remote";
      sshUser = "kylerisse";
    };
  };

  dualhome-nat.enable = true;
  dualhome-nat.internalInterface = "enp2s0";
  dualhome-nat.externalInterface = "enp1s0";
  dualhome-nat.internalCIDR = "192.168.70.0/24";

  dhcp-server.enable = true;
  dhcp-server.interfaces = [ "enp2s0" ];
  dhcp-server.dns = "192.168.73.1";
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

  system.stateVersion = "22.11";
}
