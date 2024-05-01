{ config, pkgs, modulesPath, ... }:
{
  imports =
    [
      (modulesPath + "/virtualisation/digital-ocean-image.nix")
    ];
  boot.initrd.availableKernelModules = [ "kvm-intel" "kvm-amd" "ahci" "xhci_pci" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.loader.grub.device = "/dev/vda";

  time.timeZone = "America/Los_Angeles";

  services.timesyncd.enable = false;

  networking.dhcpcd.extraConfig = "noarp";

  networking.useDHCP = true;

  nixpkgs.hostPlatform = "x86_64-linux";

  ssh-server.enable = true;

  system.stateVersion = "24.05";
}
