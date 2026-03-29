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

  mynixcfg.users.kylerisse.enable = true;
  mynixcfg.ssh-server.enable = true;
  mynixcfg.nix-common.enable = true;

  system.stateVersion = config.system.nixos.release;
}
