{ config, pkgs, lib, hostname, inputs, ... }:
{
  nix-common.enable = true;
  ssh-server.enable = true;
  networking.firewall.allowedTCPPorts = [ 80 ];
  mrtg = {
    enable = true;
    hostList = [ "switch1.risse.tv" ];
  };
  services.nginx = {
    enable = true;
    virtualHosts = {
      "corner.risse.tv" = {
        default = true;
        root = "/var/lib/mrtg/html";
        locations."/" = {
          extraConfig = ''
            autoindex on;
            autoindex_exact_size off;
            autoindex_localtime on;
          '';
        };
      };
    };
  };

  imports =
    [
      ./guests-common.nix
    ];
}
