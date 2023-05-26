{ config, pkgs, ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      passwordAuthentication = false;
      kbdInteractiveAuthentication = false;
      permitRootLogin = "no";
    };
  };
  networking.firewall.allowedTCPPorts = [ 22 ];
}
