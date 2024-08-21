{ config, pkgs, inputs, ... }:
let
  # gdm trickery
  monitorsXmlContent = builtins.readFile ./monitors.xml;
  monitorsConfig = pkgs.writeText "gdm_monitors.xml" monitorsXmlContent;

  ssh-server.enable = true;
in
{
  imports =
    [
      ./hardware-configuration.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  nix.settings = {
    trusted-users = [ "@wheel" ];
    auto-optimise-store = true;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "watson"; # Define your hostname.
  networking.extraHosts =
    ''
      192.168.73.51 kube.api
    '';

  # Enable networking
  networking = {
    networkmanager.enable = false;
    useNetworkd = true;
    firewall.enable = true;
  };

  systemd.network = {
    enable = true;
    netdevs.br0.netdevConfig = {
      Kind = "bridge";
      Name = "br0";
    };
    networks = {
      "20-enp8s0" = {
        matchConfig.Name = "enp8s0";
        networkConfig.Bridge = "br0";
        linkConfig.RequiredForOnline = "enslaved";
      };
      "30-br0" = {
        matchConfig.Name = "br0";
        enable = true;
        networkConfig.DHCP = "yes";
        linkConfig.RequiredForOnline = "routable";
        # TODO: why doesn't this work when sent via DHCP?
        domains = [ "risse.tv" ];
      };
    };
  };

  virtualisation = {
    libvirtd.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
    };

    oci-containers = {
      backend = "podman";

      containers = {
        open-webui = import ./containers/open-webui.nix;
      };
    };
  };
  programs = {
    dconf.enable = true;
    virt-manager.enable = true;
  };
  boot.extraModprobeConfig = "options kvm_amd nested=1";

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

  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.kylerisse = with pkgs; {
    shell = pkgs.fish;
    extraGroups = [ "dialout" "networkmanager" "libvirtd" ];

    packages = with pkgs; [
      awscli2
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
      helm
      htop
      icdiff
      inetutils
      jq
      k9s
      kompose
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
      openrct2
      openssh
      silver-searcher
      slack
      steam
      usbutils
      virt-manager
      vscode
      wget
      yamllint
      yubikey-manager
      inputs.self.packages.x86_64-linux.go-signs
    ];
  };

  # gnome exclusions
  environment.gnome.excludePackages = (with pkgs; [
    baobab
    epiphany
    gnome-text-editor
    # gnome-calculator
    gnome-calendar
    # gnome-characters
    gnome.gnome-clocks
    # pkgs.gnome-console
    gnome.gnome-contacts
    # gnome-font-viewer
    gnome.gnome-logs
    gnome.gnome-maps
    gnome.gnome-music
    gnome-system-monitor
    gnome.gnome-weather
    loupe
    # nautilus
    gnome-connections
    simple-scan
    snapshot
    totem
    yelp
  ]);

  # GDM should have same monitor config as the user
  systemd.tmpfiles.rules = [
    "L+ /run/gdm/.config/monitors.xml - - - - ${monitorsConfig}"
  ];

  # Create directories and run scripts for the containers
  system.activationScripts = {
    script.text = ''
      install -d -m 755 /home/kylerisse/open-webui/data -o root -g root
    '';
  };

  networking.firewall.allowedTCPPorts = [ 8080 ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
  ];

  environment.shells = with pkgs; [
    bash
    fish
  ];

  programs.fish.enable = true;
  programs.fish.useBabelfish = true;
  programs.fish.shellInit = ''
    fish_add_path --prepend /run/wrappers/bin
  '';

  ssh-server.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?

}
