# default configuration for installation as kvm guest

{ config, pkgs, ... }:

{
  imports =
    [
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

  users.users.kylerisse = {
    isNormalUser = true;
    uid = 9001;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPirA5WUlTLXEol/yr+QJDeWa3S8GW0u4TXzSxBxRrbs"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJaBu1HK/Ou9wV2Ebz7NKVsRSZEKiJfvwmcictvnu8lu"
    ];
  };

  services.openssh = {
    enable = true;
    passwordAuthentication = false;
    kbdInteractiveAuthentication = false;
    permitRootLogin = "no";
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "22.11";
}
