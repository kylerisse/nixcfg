{ config, pkgs, lib, hostname, ... }:
{
  imports =
    [
      ./guests-common.nix
    ];

  kube-cluster = {
    enable = true;
    isMaster = if hostname == "k8s-master" then true else false;
    masterIP = "192.168.73.51";
    masterHostname = "kube.api";
    masterPort = 6443;
  };
}
