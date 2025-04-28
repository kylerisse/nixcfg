{ config, pkgs, modulesPath, ... }:
{
  imports =
    [
      (modulesPath + "/virtualisation/digital-ocean-image.nix")
    ];

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.initrd.availableKernelModules = [ "kvm-intel" "kvm-amd" "ahci" "xhci_pci" "virtio_pci" "sr_mod" "virtio_blk" ];

  time.timeZone = "America/Los_Angeles";

  services.timesyncd.enable = false;

  networking.dhcpcd.extraConfig = "noarp";

  networking.useDHCP = true;

  nixpkgs.hostPlatform = "x86_64-linux";

  ssh-server.enable = true;
  nix-common.enable = true;

  services.fail2ban.enable = true;
}
