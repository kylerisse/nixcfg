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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPcTYYr/TGH4vRCaY4WU4Qc7RlzzBOHv2XYxGwCzV+fg p"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKX8NM1OQECwhNTQE0qAm422uq9L0i0Y/hvPPc4tHIOX a"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDwETBVGk/A/3TZgmB/lVy7KZdY62ywNODx3HJk698PP a"
    ];
  };

  services.openssh = {
    enable = true;
  };
  networking.firewall.allowedTCPPorts = [ 22 ];
}
