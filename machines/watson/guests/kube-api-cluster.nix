{ config, pkgs, lib, hostname, inputs, ... }:
let
  pkgs-unstable = import inputs.nixos-unstable {
    system = "x86_64-linux";
    config = { allowUnfree = true; };
  };
in
{
  imports =
    [
      ./guests-common.nix
    ];

  kube-cluster = {
    enable = true;
    package = pkgs-unstable.kubernetes;
    isMaster = if hostname == "k8s-master" then true else false;
    masterIP = "192.168.73.51";
    masterHostname = "kube.api";
    masterPort = 6443;
  };
}
