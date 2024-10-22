{ config, pkgs, lib, ... }:
let
  cfg = config.kube-cluster;
in
{
  options.kube-cluster = {
    enable = lib.mkEnableOption (lib.mdDoc "Kubernetes Cluster");
    isMaster = lib.mkEnableOption (lib.mdDoc "Is the master node");
    masterIP = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Master IP";
    };
    masterHostname = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Master Hostname";
    };
    masterPort = lib.mkOption {
      type = lib.types.int;
      default = 6443;
      description = "Master TCP Port";
    };
  };
  config =
    let
      kubeApi = "https://${cfg.masterHostname}:${toString cfg.masterPort}";
    in
    lib.mkIf cfg.enable {
      services.kubernetes = {
        masterAddress = cfg.masterHostname;
        apiserverAddress = kubeApi;
        easyCerts = true;
        addons.dns.enable = true;
        kubelet.extraOpts = "--fail-swap-on=false";
        apiserver = lib.mkIf cfg.isMaster {
          securePort = cfg.masterPort;
          advertiseAddress = cfg.masterIP;
          allowPrivileged = false;
        };
        roles = if cfg.isMaster then [ "master" "node" ] else [ "node" ];
      };
      networking.firewall.enable = false;
      environment.systemPackages = with pkgs; [
        helm
        k9s
        kompose
        kubectl
        kubectx
        kubernetes
        git
        vim
      ];
    };
}
