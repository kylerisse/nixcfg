{ config, lib, pkgs, nixpkgs, hostname, ... }:

{
  nix-common.enable = true;
  ssh-server.enable = true;

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = hostname;
  time.timeZone = "America/Los_Angeles";

  environment.systemPackages = with pkgs; [
    vim
  ];

  kube-cluster = {
    enable = true;
    isMaster = false;
    masterIP = "192.168.73.4";
    masterHostname = "qube";
    masterPort = 6443;
  };

  networking.extraHosts =
    ''
      192.168.73.4 qube
      192.168.73.2 pi3
      192.168.73.3 pi4
    '';
}

