{ config, pkgs, ... }:
let
  internalInterface = "enp2s0";
  externalInterface = "enp1s0";
  internalCIDR = "192.168.32.0/24";
in
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
  };

  # TODO: this to ### should be in the router module
  boot = {
    kernel.sysctl = {
      "net.ipv6.conf.${externalInterface}.accept_ra" = 2;
      "net.ipv6.conf.${externalInterface}.autoconf" = true;
    };
  };

  networking.nat = {
    inherit externalInterface;
    internalInterfaces = [ internalInterface ];
    internalIPs = [ internalCIDR ];
  };
  ###

  time.timeZone = "America/Los_Angeles";

  system.stateVersion = "22.11";
}
