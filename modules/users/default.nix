{ config, pkgs, ... }:
{
  users.users.kylerisse = {
    isNormalUser = true;
    uid = 9001;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPirA5WUlTLXEol/yr+QJDeWa3S8GW0u4TXzSxBxRrbs"
    ];
  };
  security.sudo.wheelNeedsPassword = false;
}
