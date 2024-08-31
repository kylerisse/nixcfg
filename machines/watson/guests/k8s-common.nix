{ config, pkgs, lib, modulesPath, hostname, ... }:
{
  nix-common.enable = true;

  imports =
    [
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  networking.hostName = hostname;

  fileSystems."/" =
    {
      device = "/dev/vda1";
      fsType = "ext4";
    };
  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Bootloader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.useOSProber = true;

  networking.networkmanager.enable = true;

  time.timeZone = "America/Los_Angeles";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  users.users.devops = {
    isNormalUser = true;
    description = "devops";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [ ];
  };
  services.getty.autologinUser = "devops";

  environment.systemPackages = with pkgs; [
    helm
    k9s
    kompose
    kubectl
    kubectx
    kubernetes
    git
    vim
  ];

  system.stateVersion = "24.05";

  networking.extraHosts =
    ''
      192.168.73.51 kube.api
      192.168.73.51 k8s-master
      192.168.73.52 k8s-worker1
      192.168.73.53 k8s-worker2
      192.168.73.54 db
    '';
  ssh-server.enable = true;
}
