{ config, lib, pkgs, modulesPath, ... }:

{
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.initrd.availableKernelModules = [ "kvm_amd" "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "uas" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "amd-pstate" ];
  boot.kernelParams = [ "amd_pstate=active" ];
  boot.extraModulePackages = [ ];


  fileSystems."/boot" =
    {
      device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
    };

  boot.initrd.luks.devices."enc-nixroot".device = "/dev/disk/by-label/CRYPT_NIXROOT";

  fileSystems."/" =
    {
      device = "/dev/disk/by-label/NIXROOT";
      fsType = "ext4";
      options = [ "noatime" "nodiratime" "discard" ];
    };

  boot.initrd.luks.devices."enc-home".device = "/dev/disk/by-label/CRYPT_HOME";

  fileSystems."/home" =
    {
      device = "/dev/disk/by-label/HOME";
      fsType = "ext4";
      options = [ "noatime" "nodiratime" "discard" ];
    };

  boot.initrd.luks.devices."enc-backup".device = "/dev/disk/by-label/CRYPT_BACKUP";

  fileSystems."/backup" =
    {
      device = "/dev/disk/by-label/BACKUP";
      fsType = "ext4";
    };

  boot.initrd.luks.devices."enc-swap".device = "/dev/disk/by-label/CRYPT_SWAP";

  swapDevices = [{
    device = "/dev/disk/by-label/SWAP";
  }];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # allow emulation for raspberry pis
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Enable OpenGL
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
