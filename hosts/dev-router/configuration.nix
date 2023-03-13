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

  networking = {
    hostName = "dev-router";
    interfaces = {
      enp1s0.useDHCP = true;
      enp2s0.ipv4.addresses = [{
        address = "192.168.70.1";
        prefixLength = 24;
      }];
    };
    firewall.allowedTCPPorts = [ 22 ];
  };

  time.timeZone = "America/Los_Angeles";

  system.stateVersion = "22.11";
}
