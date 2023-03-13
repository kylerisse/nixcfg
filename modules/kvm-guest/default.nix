{ config, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.device = "/dev/vda";

  time.timeZone = "America/Los_Angeles";

  services.getty.autologinUser = "root";
  services.qemuGuest.enable = true;
  services.timesyncd.enable = false;

  networking.dhcpcd.extraConfig = "noarp";
}
