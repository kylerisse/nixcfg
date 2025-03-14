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
}

