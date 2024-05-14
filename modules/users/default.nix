{ config, pkgs, ... }:
{
  users.users.kylerisse = {
    isNormalUser = true;
    uid = 9001;
    description = "kylerisse";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPirA5WUlTLXEol/yr+QJDeWa3S8GW0u4TXzSxBxRrbs"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILd1LH8ULHcy7jk0GtajE2N5EIjzoytcgylAYc6CzR6+"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICsFjPrXwIcG1uJER9JTIVQVfiBMrXqDfmnFKZJG8bCm"
    ];
  };
  security.sudo.wheelNeedsPassword = false;
}
