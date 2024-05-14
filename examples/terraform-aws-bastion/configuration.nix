{
  imports = [ <nixpkgs/nixos/modules/virtualisation/amazon-image.nix> ];
  ec2.hvm = true;

  security.sudo.wheelNeedsPassword = false;
  nix.settings.trusted-users = [ "@wheel" ];

  services.openssh = {
    enable = true;
    passwordAuthentication = false;
    kbdInteractiveAuthentication = false;
  };
  networking.firewall.allowedTCPPorts = [ 22 ];

  users.users.kylerisse = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPirA5WUlTLXEol/yr+QJDeWa3S8GW0u4TXzSxBxRrbs"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILd1LH8ULHcy7jk0GtajE2N5EIjzoytcgylAYc6CzR6+"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICsFjPrXwIcG1uJER9JTIVQVfiBMrXqDfmnFKZJG8bCm"
    ];
  };

  users.users.luser = {
    isNormalUser = true;

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAABBBBCCCCDDDDEEEEFFFFabcdefghijklmnopqrstuvwxyzzyxwvutsrqponmlkji"
    ];
  };

  system.stateVersion = "22.11";
}
