{ config, lib, pkgs, nixpkgs, hostname, inputs, ... }:

{
  mynixcfg.users.kylerisse.enable = true;
  mynixcfg.nix-common.enable = true;
  mynixcfg.ssh-server.enable = true;

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = hostname;
  time.timeZone = "America/Los_Angeles";

  environment.systemPackages = with pkgs; [
    vim
  ];

  networking.firewall.allowedTCPPorts = [ 2017 ];
  mynixcfg.scale-signs = {
    enable = true;
    jsonEndpoint = "http://qube.risse.tv:2018/sign.json";
    refreshInterval = 1;
  };

  system.stateVersion = "25.11";
}

