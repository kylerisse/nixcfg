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

  dualhome-nat.internalInterface = "enp2s0";
  dualhome-nat.externalInterface = "enp1s0";
  dualhome-nat.internalCIDR = "192.168.70.0/24";

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
