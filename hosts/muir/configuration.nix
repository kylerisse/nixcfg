{ config, lib, pkgs, modulePath, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  nix.settings = {
    trusted-users = [ "@wheel" ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "muir";
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties.
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

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };

  # Enable sound with pulseaudio.
  sound.enable = true;
  hardware.pulseaudio.enable = true;
  security.rtkit.enable = true;

  # touchpad
  services.libinput.enable = true;

  users.users.kylerisse = {
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" ];

    packages = with pkgs; [
      bitwarden
      brave
      btop
      chezmoi
      curl
      dig
      discord
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
  environment.gnome.excludePackages = (with pkgs.gnome; [
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

  environment.systemPackages = with pkgs; [
    vim
  ];

  environment.shells = with pkgs; [
    bash
    fish
  ];

  programs.fish.enable = true;
  programs.fish.shellInit = ''
    fish_add_path --prepend /run/wrappers/bin
  '';

  system.stateVersion = "24.05";
}
