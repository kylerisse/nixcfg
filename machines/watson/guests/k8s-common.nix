{ config, pkgs, lib, modulesPath, hostname, ... }:
{
  imports =
    [
      ./guests-common.nix
    ];

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
}
