{ config, lib, pkgs, inputs, ... }:
let
  pkgs-unstable = import inputs.nixos-unstable {
    system = "x86_64-linux";
    config = { allowUnfree = true; };
  };
in
{
  nix-common.enable = true;

  hardware = {
    enableRedistributableFirmware = lib.mkDefault true;
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    graphics = {
      enable = true;
      enable32Bit = true;
    };
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    initrd = {
      availableKernelModules = [ "kvm_intel" "xhci_pci" "ahci" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" ];
      kernelModules = [ ];
      luks.devices = {
        "enc-nixroot".device = "/dev/disk/by-label/CRYPT_NIXROOT";
        "enc-swap".device = "/dev/disk/by-label/CRYPT_SWAP";
      };
    };
    kernelModules = [ ];
    extraModulePackages = [ ];
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    binfmt.emulatedSystems = [ "aarch64-linux" ];
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXROOT";
      fsType = "ext4";
      options = [ "noatime" "nodiratime" "discard" ];
    };
    "/boot" = {
      device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };
  };

  swapDevices = [{
    device = "/dev/disk/by-label/SWAP";
  }];

  networking = {
    hostName = "muir";
    useDHCP = lib.mkDefault true;
    networkmanager.enable = true;
    nftables.enable = true;
    firewall.allowPing = false;
  };

  ssh-server.enable = false;

  time.timeZone = "America/Los_Angeles";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
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
  };

  services = {
    xserver = {
      enable = true;
      displayManager.gdm.enable = true;
      desktopManager.gnome.enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };
    # touchpad
    libinput.enable = true;
  };

  virtualisation = {
    libvirtd.enable = true;
    docker = {
      enable = true;
      rootless = {
        enable = true;
        setSocketVariable = true;
      };
    };
  };

  security.rtkit.enable = true;

  users.users.kylerisse = {
    shell = pkgs.fish;
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "dialout" "docker" ];

    packages = with pkgs; [
      bitwarden
      brave
      btop
      chezmoi
      curl
      cyberchef
      dig
      discord
      dive
      element-desktop
      firefox
      gcc
      git
      go
      gopls
      go-outline
      gnumake
      htop
      icdiff
      inetutils
      jq
      k9s
      kubectl
      kubectx
      libressl
      mudlet
      netcat
      nixpkgs-fmt
      nmap
      nodePackages.cspell
      nodePackages.jsonlint
      nodePackages_latest.markdownlint-cli
      openssh
      python312
      python312Packages.meshtastic
      python312Packages.pypubsub
      silver-searcher
      slack
      unzip
      vim
      virt-manager
      vscode
      wget
      yamllint
      zip
    ];
  };

  # gnome exclusions
  environment = {
    gnome.excludePackages = (with pkgs.gnome; [
      baobab
      epiphany
      pkgs.gnome-text-editor
      # gnome-calculator
      gnome-calendar
      # gnome-characters
      gnome-clocks
      # pkgs.gnome-console
      gnome-contacts
      # gnome-font-viewer
      gnome-logs
      gnome-maps
      gnome-music
      gnome-system-monitor
      gnome-weather
      pkgs.loupe
      # nautilus
      pkgs.gnome-connections
      simple-scan
      pkgs.snapshot
      totem
      yelp
    ]);
    systemPackages = with pkgs; [
      vim
    ];
    shells = with pkgs; [
      bash
      fish
    ];
  };

  programs = {
    fish = {
      enable = true;
      shellInit = ''
        fish_add_path --prepend /run/wrappers/bin
      '';
    };
    virt-manager.enable = true;
  };
}
