{ config, pkgs, lib, modulesPath, hostname, ... }:
{
  imports =
    [
      ./guests-common.nix
    ];

  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    authentication = pkgs.lib.mkOverride 10 ''
      local all all trust
      host all all 127.0.0.1/32 trust
      host all all 192.168.73.0/24 trust
      host all all ::1/128 trust
    '';
  };
  networking.firewall.allowedTCPPorts = [ 5432 ];
}
