{ config, pkgs, lib, ... }:
let
  kubeMasterIP = "192.168.73.51";
  kubeMasterHostname = "kube.api";
  kubeMasterAPIServerPort = 6443;
in
{
  services.kubernetes = {
    roles = [ "master" "node" ];
    masterAddress = kubeMasterHostname;
    apiserverAddress = "https://${kubeMasterHostname}:${toString kubeMasterAPIServerPort}";
    easyCerts = true;
    apiserver = {
      securePort = kubeMasterAPIServerPort;
      advertiseAddress = kubeMasterIP;
      allowPrivileged = true;
    };
    addons.dns.enable = true;
  };
  networking.firewall.enable = false;
}
