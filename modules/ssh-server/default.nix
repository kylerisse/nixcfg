{ config, pkgs, ... }:
{
  services.openssh = {
    enable = true;
    passwordAuthentication = false;
    kbdInteractiveAuthentication = false;
    permitRootLogin = "no";
  };
  networking.firewall.allowedTCPPorts = [ 22 ];
}