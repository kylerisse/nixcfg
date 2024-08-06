{ config, lib, pkgs, ... }:

{
  boot = {
    binfmt.emulatedSystems = [ "aarch64-linux" ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
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
    extraModprobeConfig = "options kvm_intel nested=1";
  };

  fileSystems = {
    "/" = {
      device = "/dev/mapper/enc-nixroot";
      fsType = "ext4";
      options = [ "noatime" "nodiratime" "discard" ];
    };
    "/boot" = {
      device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
    };
  };

  swapDevices = [{
    device = "/dev/disk/by-label/SWAP";
  }];

  networking = {
    useDHCP = lib.mkDefault true;
    hostName = "riviera";
    networkmanager.enable = true;
  };

  hardware = {
    enableRedistributableFirmware = lib.mkDefault true;
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    opengl = {
      enable = true;
      driSupport = true;
      driSupport32Bit = true;
    };
    pulseaudio.enable = true;
  };

  nix.settings = {
    trusted-users = [ "@wheel" ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
  nixpkgs.config.allowUnfree = true;

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
    libinput.enable = true;
  };

  sound.enable = true;

  security = {
    rtkit.enable = true;
    sudo.wheelNeedsPassword = false;
  };

  users.users.kylerisse = {
    shell = pkgs.fish;
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "dialout" "docker" ];
    isNormalUser = true;
    uid = 9001;
    description = "kylerisse";

    packages = with pkgs; [
      brave
      btop
      chezmoi
      curl
      dig
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
      neovim
      netcat
      nixpkgs-fmt
      nmap
      nodePackages.cspell
      nodePackages.jsonlint
      nodePackages_latest.markdownlint-cli
      openssh
      silver-searcher
      slack
      virt-manager
      vscode
      wget
      yamllint
    ];
  };

  # gnome exclusions
  environment = {
    systemPackages = with pkgs; [
      vim
    ];
    shells = with pkgs; [
      bash
      fish
    ];
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
  };

  programs = {
    fish.enable = true;
    fish.shellInit = ''
      fish_add_path --prepend /run/wrappers/bin
    '';
    dconf.enable = true;
    virt-manager.enable = true;
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

  system.stateVersion = "24.11";
}
