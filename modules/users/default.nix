{ config, pkgs, ... }:
{
  users.users.kylerisse = {
    isNormalUser = true;
    uid = 9001;
    description = "ls";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPcTYYr/TGH4vRCaY4WU4Qc7RlzzBOHv2XYxGwCzV+fg p"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKX8NM1OQECwhNTQE0qAm422uq9L0i0Y/hvPPc4tHIOX a"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDwETBVGk/A/3TZgmB/lVy7KZdY62ywNODx3HJk698PP a"
    ];
  };
  security.sudo.wheelNeedsPassword = false;
}
