{ config, pkgs, lib, ... }:
let
  kubeMasterIP = "192.168.73.51";
  kubeMasterHostname = "kube.api";
  kubeMasterAPIServerPort = 6443;
in
{
  services.kubernetes =
    let
      api = "https://${kubeMasterHostname}:${toString kubeMasterAPIServerPort}";
    in
    {
      roles = [ "node" ];
      masterAddress = kubeMasterHostname;
      easyCerts = true;
      kubelet.kubeconfig.server = api;
      apiserverAddress = api;
      addons.dns.enable = true;
    };
  networking.firewall.enable = false;
}
