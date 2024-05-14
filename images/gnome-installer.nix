{ config, pkgs, modulesPath, ... }:
{
  imports =
    [
      (modulesPath + "/installer/cd-dvd/installation-cd-graphical-calamares-gnome.nix")
      (modulesPath + "/installer/cd-dvd/channel.nix")
    ];

  nix.settings = {
    trusted-users = [ "@wheel" ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    dosfstools
    fish
  ];

  users.users.nixos = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPirA5WUlTLXEol/yr+QJDeWa3S8GW0u4TXzSxBxRrbs"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILd1LH8ULHcy7jk0GtajE2N5EIjzoytcgylAYc6CzR6+"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICsFjPrXwIcG1uJER9JTIVQVfiBMrXqDfmnFKZJG8bCm"
    ];
  };

  services.openssh = {
    enable = true;
  };
  networking.firewall.allowedTCPPorts = [ 22 ];
}
