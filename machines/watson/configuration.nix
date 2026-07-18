{ config, pkgs, inputs, ... }:
let
  pkgs-unstable = import inputs.nixos-unstable {
    system = "x86_64-linux";
    config = { allowUnfree = true; };
  };
  pkgs-master = import inputs.nixos-master {
    system = "x86_64-linux";
    config = { allowUnfree = true; };
  };
in
{
  mynixcfg.users.kylerisse.enable = true;
  mynixcfg.nix-common = {
    enable = true;
    autoGC = false;
  };

  # electron 39 is EOL upstream but still required by bitwarden-desktop
  # and other electron apps on nixos-26.05
  # https://github.com/NixOS/nixpkgs/issues/526914
  # https://github.com/bitwarden/clients/issues/21581
  nixpkgs.config.permittedInsecurePackages = [
    "electron-39.8.10"
  ];
  mynixcfg.alloy = {
    enable = true;
    enableTracing = true;
    enableNvidiaGpu = true;
  };
  mynixcfg.nvidia-fan-curve.enable = true;
  imports =
    [
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
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
      "20-enp5s0" = {
        matchConfig.Name = "enp5s0";
        networkConfig = {
          Bridge = "br0";
          DHCP = "no";
          LinkLocalAddressing = "no";
        };
        linkConfig.RequiredForOnline = "enslaved";
      };
      "30-br0" = {
        matchConfig.Name = "br0";
        enable = true;
        networkConfig = {
          DHCP = "yes";
          DNSDefaultRoute = true;
        };
        linkConfig.RequiredForOnline = "routable";
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
  };
  programs = {
    dconf.enable = true;
    virt-manager.enable = true;
  };
  boot.kernelParams = [ "pcie_aspm=off" ];
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
  services.xserver.desktopManager.cinnamon.enable = true;
  services.xserver.displayManager.lightdm.enable = true;

  services.printing.enable = true;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };

  services.pulseaudio.enable = false;
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

    packages =
      let
        stablePackages = with pkgs; [
          bitwarden-desktop
          brave
          chezmoi
          cspell
          curl
          direnv
          firefox
          ghostty
          git
          gnumake
          icdiff
          jq
          libressl
          markdownlint-cli
          nixpkgs-fmt
          openssh
          podman-compose
          prettier
          silver-searcher
          vim
          virt-manager
          vscode
          wget
          xterm
          yubikey-manager
        ];

        unstablePackages = with pkgs-unstable; [
          discord
          element-desktop
          go
          gopls
          go-outline
          signal-desktop
          slack
          spotify
          steam
        ];

        masterPackages = with pkgs-master; [
          claude-code
          openrct2
        ];

        selfPackages = [
          inputs.self.packages.x86_64-linux.docket-unstable
          inputs.self.packages.x86_64-linux.sdl-ss-inhibitors
          inputs.self.packages.x86_64-linux.sdl-ss-inhibitors-tray
        ];
      in
      stablePackages ++ unstablePackages ++ masterPackages ++ selfPackages;
  };

  environment.systemPackages =
    let
      basePackages = with pkgs; [
        btop
        dig
        htop
        netcat
        nmap
        usbutils
        vim
      ];
      uTools = with pkgs.unixtools; [
        arp
        netstat
        ping
        route
      ];
    in
    basePackages ++ uTools;

  environment.shells = with pkgs; [
    bash
    fish
  ];

  programs.fish.enable = true;
  programs.fish.useBabelfish = true;
  programs.fish.shellInit = ''
    fish_add_path --prepend /run/wrappers/bin
  '';

  mynixcfg.ssh-server.enable = true;

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    loadModels = [
      # multimodal (vision + text)
      "gemma3:12b" # ~8GB
      "llama3.2-vision:11b" # ~8GB
      # coding
      "codegemma:7b" # ~5GB
      "granite-code:8b" # ~5GB
      # reasoning / general purpose
      "phi4:14b" # ~9GB
      # general purpose
      "mistral:7b" # ~4GB
      "llama3.1:8b" # ~5GB
      # lightweight general purpose
      "phi4-mini:3.8b" # ~2.5GB
      "gemma3:4b" # ~3GB
    ];
    environmentVariables = {
      OLLAMA_NUM_PARALLEL = "1";
      OLLAMA_MAX_LOADED_MODELS = "1";
    };
  };
  services.open-webui = {
    enable = true;
    environment = {
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
      OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
      WEBUI_URL = "https://ai.risse.tv";
    };
    host = "127.0.0.1";
    port = 3088;
    openFirewall = false;
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "kylerisse@users.noreply.github.com";
      dnsProvider = "route53";
      environmentFile = "/etc/acme/aws.key";
      dnsPropagationCheck = true;
      dnsResolver = "1.1.1.1:53";
    };
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts."ai.risse.tv" = {
      onlySSL = true;
      enableACME = true;
      acmeRoot = null;
      locations."/" = {
        proxyPass = "http://127.0.0.1:3088/";
        proxyWebsockets = true;
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 443 ];

  system.stateVersion = "25.11";
}
