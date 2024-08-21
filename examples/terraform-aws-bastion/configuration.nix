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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPcTYYr/TGH4vRCaY4WU4Qc7RlzzBOHv2XYxGwCzV+fg p"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKX8NM1OQECwhNTQE0qAm422uq9L0i0Y/hvPPc4tHIOX a"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMlEPbMnefiPfCTKb9lOzPzfnOVAohO08myWWMm9EJxZ"
    ];
  };

  users.users.luser = {
    isNormalUser = true;

    openssh.authorizedKeys.keys = [
    ];
  };

  system.stateVersion = "22.11";
}
