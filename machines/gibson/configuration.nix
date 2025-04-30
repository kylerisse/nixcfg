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

  environment.etc = {
    # taken from https://nixos.wiki/wiki/Fail2ban
    # Defines a filter that detects URL probing by reading the Nginx access log
    "fail2ban/filter.d/nginx-url-probe.local".text = pkgs.lib.mkDefault (pkgs.lib.mkAfter ''
      [Definition]
      failregex = ^<HOST>.*(GET /(wp-|admin|boaform|phpmyadmin|\.env|\.git)|\.(dll|so|cfm|asp)|(\?|&)(=PHPB8B5F2A0-3C92-11d3-A3A9-4C7B08C10000|=PHPE9568F36-D428-11d2-A769-00AA001ACF42|=PHPE9568F35-D428-11d2-A769-00AA001ACF42|=PHPE9568F34-D428-11d2-A769-00AA001ACF42)|\\x[0-9a-zA-Z]{2})
    '');
  };
  services.fail2ban = {
    enable = true;
    maxretry = 2;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      multipliers = "1 2 4 8 16 32 64";
      overalljails = true;
    };
    jails = {
      "nginx-url-probe".settings = {
        enabled = true;
        filter = "nginx-url-probe";
        logpath = "/var/log/nginx/access.log";
        backend = "auto";
        action = "%(action_)s[blocktype=DROP]";
      };
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
