{ config, pkgs, modulesPath, inputs, ... }:
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

  ssh-server.enable = true;
  nix-common.enable = true;

  services.fail2ban = {
    enable = true;
    maxretry = 2;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      multipliers = "1 2 4 8 16 32 64";
      overalljails = true;
    };
  };

  scale-simulator.enable = true;
  go-signs = {
    enable = true;
    xmlEndpoint = "http://localhost:2018/sign.xml";
    refreshInterval = 1;
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "kylerisse@users.noreply.github.com";
    certs."go-signs.org".extraDomainNames = [
      "demo.go-signs.org"
      "simulator.go-signs.org"
    ];
  };
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  services.nginx = {
    enable = true;
    virtualHosts = {
      "go-signs.org" = {
        default = true;
        enableACME = true;
        forceSSL = true;
        serverAliases = [
          "www.go-signs.org"
        ];
        locations."/" = {
          extraConfig = ''
            return 301 https://github.com/kylerisse/go-signs;
          '';
        };
      };
      "demo.go-signs.org" = {
        useACMEHost = "go-signs.org";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:2017";
        };
      };
      "simulator.go-signs.org" = {
        useACMEHost = "go-signs.org";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:2018";
        };
      };
    };
  };
}
