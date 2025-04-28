{ config, pkgs, lib, modulesPath, inputs, ... }:
{
  nix-common.enable = true;
  ssh-server.enable = true;
  networking.firewall.allowedTCPPorts = [ 80 2018 ];
  mrtg = {
    enable = true;
    hostList = [ "switch1.risse.tv" ];
    nginxEnable = true;
    nginxVhosts = [ "mrtg.risse.tv" ];
  };
  wasgeht = {
    enable = true;
    package = inputs.self.packages.x86_64-linux.wasgeht-unstable;
    hostFile = builtins.toFile "hosts.json" ''
      {
        "zzmodem": {
          "address": "192.168.254.254"
        },
        "zzisp": {
          "address": "47.155.20.1"
        },
        "zzdns1": {
          "address": "1.0.0.1"
        },
        "zzdns2": {
          "address": "1.1.1.1"
        },
        "router": {},
        "pi3": {},
        "pi4": {},
        "qube": {},
        "switch1": {},
        "ap1": {},
        "ap2": {},
        "solar": {},
        "watson": {},
        "zugzug": {}
      }
    '';
    nginxEnable = true;
    nginxVhosts = [
      "wasgeht.risse.tv"
      "whatsup.risse.tv"
    ];
  };
  scale-simulator.enable = true;

  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "usbhid" "sd_mod" "sdhci_pci" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];
  boot.kernelPackages = pkgs.linuxPackages_latest;

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXROOT";
    fsType = "ext4";
  };
  fileSystems."/home" = {
    device = "/dev/disk/by-label/HOME";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [{
    device = "/dev/disk/by-label/SWAP";
  }];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "qube";
  networking.wireless.enable = false;

  networking.networkmanager.enable = false;
  networking.useNetworkd = true;

  systemd.network = {
    enable = true;
    netdevs.br0.netdevConfig = {
      Kind = "bridge";
      Name = "br0";
    };
    networks = {
      "20-enp1s0" = {
        matchConfig.Name = "enp1s0";
        networkConfig.Bridge = "br0";
        linkConfig.RequiredForOnline = "enslaved";
      };
      "30-br0" = {
        matchConfig.Name = "br0";
        enable = true;
        networkConfig.DHCP = "yes";
        linkConfig.RequiredForOnline = "routable";
        domains = [ "risse.tv" ];
      };
    };
  };

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

  environment.systemPackages = with pkgs; [
  ];
}
