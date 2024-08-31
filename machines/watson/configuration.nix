{ config, pkgs, inputs, ... }:
let
  # gdm trickery
  monitorsXmlContent = builtins.readFile ./monitors.xml;
  monitorsConfig = pkgs.writeText "gdm_monitors.xml" monitorsXmlContent;
in
{
  nix-common.enable = true;

  imports =
    [
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "watson";
  networking.extraHosts =
    ''
      192.168.73.51 kube.api
    '';

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

  services.xserver.enable = true;

  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

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
      install -d -m 755 /home/open-webui/ -o root -g root
    '';
  };

  networking.firewall.allowedTCPPorts = [ 8080 ];

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
}
