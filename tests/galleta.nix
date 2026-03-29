{ lib, network, inputs, nixpkgs, galletaConfig, allModule }:
{
  name = "galleta";

  nodes = {
    galleta = { pkgs, ... }: {
      imports = [
        allModule
        galletaConfig
      ];

      _module.args = { inherit network inputs nixpkgs; };

      virtualisation.vlans = [ 1 2 ];

      # Disable modules not applicable in VM test
      mynixcfg.nix-common.enable = lib.mkForce false;

      # Remap interfaces for VM
      galleta.lanInterface = lib.mkForce "eth1";
      galleta.wanInterface = lib.mkForce "eth2";

      networking.bridges = lib.mkForce { };
      networking.sits = lib.mkForce { };
      networking.defaultGateway6 = lib.mkForce null;
      networking.interfaces = lib.mkForce {
        eth1.ipv4.addresses = [{
          address = "192.168.73.1";
          prefixLength = 24;
        }];
        eth1.ipv6.addresses = [{
          address = "2001:470:d:461::1";
          prefixLength = 64;
        }];
        eth2.ipv4.addresses = [{
          address = "10.0.0.1";
          prefixLength = 24;
        }];
        eth2.ipv6.addresses = [{
          address = "fd00:dead::1";
          prefixLength = 64;
        }];
      };

      # Point HE tunnel updater at mock on external node
      mynixcfg.he-tunnel-update.updateUrl = lib.mkForce "http://10.0.0.2/nic/update";

      environment.systemPackages = [ pkgs.bind ];
    };

    client = { pkgs, ... }: {
      virtualisation.vlans = [ 1 ];
      networking.useDHCP = false;
      networking.interfaces.eth1 = {
        useDHCP = true;
        ipv6.addresses = [{
          address = "2001:470:d:461::100";
          prefixLength = 64;
        }];
      };
      environment.systemPackages = [ pkgs.ldns pkgs.curl pkgs.ntp ];
    };

    external = { pkgs, ... }: {
      virtualisation.vlans = [ 2 ];
      networking.interfaces.eth1 = {
        ipv4.addresses = [{
          address = "10.0.0.2";
          prefixLength = 24;
        }];
        ipv6.addresses = [{
          address = "fd00:dead::2";
          prefixLength = 64;
        }];
      };
      services.nginx = {
        enable = true;
        virtualHosts.default.locations = {
          "/".return = "200 'hello from external'";
          "/nic/update".extraConfig = ''
            access_log /var/log/nginx/he-update.log;
            return 200 "good 10.0.0.1\n";
          '';
        };
      };
      networking.firewall.allowedTCPPorts = [ 80 ];
      environment.systemPackages = [ pkgs.ldns pkgs.nmap pkgs.ntp ];
    };
  };

  testScript = { nodes, ... }: ''
    start_all()

    # Wait for galleta services
    galleta.wait_for_unit("bind.service")
    galleta.wait_for_unit("kea-dhcp4-server.service")
    galleta.wait_for_unit("chronyd.service")
    galleta.wait_for_unit("sshd.service")
    galleta.wait_for_unit("radvd.service")

    # Validate BIND config
    galleta.succeed("named-checkconf ${nodes.galleta.services.bind.configFile}")

    # Client gets DHCP lease on correct subnet
    client.wait_until_succeeds("ip addr show eth1 | grep '192.168.73'", timeout=30)

    # Forward DNS lookup (IPv4)
    client.wait_until_succeeds("drill @192.168.73.1 qube.risse.tv A | grep '192.168.73.4'", timeout=30)

    # Forward DNS lookup (IPv6)
    client.succeed("drill @2001:470:d:461::1 qube.risse.tv A | grep '192.168.73.4'")

    # CNAME resolution
    client.succeed("drill @192.168.73.1 mrtg.risse.tv | grep 'qube.risse.tv'")

    # Reverse DNS lookup
    client.succeed("drill @192.168.73.1 -x 192.168.73.4 | grep 'qube.risse.tv'")

    # NTP is reachable from client (stratum 16 = unsynchronized, expected in VM)
    client.succeed("(ntpdate -q 192.168.73.1 2>&1 || true) | grep 'server 192.168.73.1'")

    # SSH is reachable from LAN
    client.succeed("nc -z -w 5 192.168.73.1 22")

    # LAN IPv6 connectivity
    client.succeed("ping -6 -c 1 -W 2 2001:470:d:461::1")

    # NAT test
    external.wait_for_unit("nginx.service")

    # galleta can reach external directly (sanity check)
    galleta.succeed("ping -c 1 -W 2 10.0.0.2")
    galleta.succeed("ping -6 -c 1 -W 2 fd00:dead::2")

    # Client reaches external through NAT
    client.wait_until_succeeds("curl --fail --max-time 5 http://10.0.0.2", timeout=30)

    # Verify masquerade: external sees galleta's WAN IP, not client's LAN IP
    external.succeed("grep '10.0.0.1' /var/log/nginx/access.log")
    external.fail("grep '192.168.73' /var/log/nginx/access.log")

    # Verify nftables masquerade rule exists
    galleta.succeed("nft list ruleset | grep masquerade")

    # Firewall: WAN IPv4 ICMP is rate-limited but allowed
    external.succeed("ping -c 1 -W 2 10.0.0.1")

    # Firewall: WAN IPv6 ICMP is rate-limited but allowed
    external.succeed("ping -6 -c 1 -W 2 fd00:dead::1")

    # Firewall: external cannot reach DNS (IPv4)
    external.fail("timeout 5 drill @10.0.0.1 risse.tv A")

    # Firewall: external cannot reach DNS (IPv6)
    external.fail("timeout 5 drill @fd00:dead::1 risse.tv A")

    # Firewall: external cannot reach SSH (IPv4)
    external.fail("nmap -Pn -p 22 --host-timeout 5s 10.0.0.1 | grep open")

    # Firewall: external cannot reach SSH (IPv6)
    external.fail("nmap -6 -Pn -p 22 --host-timeout 5s fd00:dead::1 | grep open")

    # Firewall: external cannot reach NTP
    external.fail("(ntpdate -q -t 2 10.0.0.1 2>&1 || true) | grep 'server 10.0.0.1'")

    # External cannot route into internal network
    external.fail("ping -c 1 -W 2 192.168.73.1")
    external.fail("ping -c 1 -W 2 192.168.73.100")

    # rp_filter drops spoofed source from internal range on WAN interface
    external.fail("nping --icmp -c 1 --source-ip 192.168.73.50 10.0.0.1 2>&1 | grep 'RCVD'")

    # Confirm rp_filter is enabled
    galleta.succeed("cat /proc/sys/net/ipv4/conf/all/rp_filter | grep 1")

    # HE tunnel updater: write test credentials and run service
    galleta.succeed("printf 'test_tunnel_id\ntest_user\ntest_key\n' > /etc/he-tunnel/credentials")
    galleta.succeed("chmod 600 /etc/he-tunnel/credentials")

    galleta.wait_for_unit("he-tunnel-update.timer")
    galleta.succeed("systemctl start he-tunnel-update.service")

    # Verify mock received the request with correct tunnel ID
    mock_he_log = "/var/log/nginx/he-update.log"
    external.wait_until_succeeds(f"test -s {mock_he_log}", timeout=10)
    external.succeed(f"grep 'hostname=test_tunnel_id' {mock_he_log}")

    # Verify service logged success
    galleta.succeed("journalctl -u he-tunnel-update.service | grep 'good 10.0.0.1'")

    # Verify dhcpcd hook is configured
    galleta.succeed("cat /etc/dhcpcd.exit-hook | grep 'he-tunnel-update'")

    # Simulate DHCP events triggering the update via the exit hook
    external.succeed(f"truncate -s 0 {mock_he_log}")
    galleta.succeed("interface=eth2 reason=BOUND /bin/sh /etc/dhcpcd.exit-hook")
    external.wait_until_succeeds(f"test -s {mock_he_log}", timeout=10)
    external.succeed(f"grep 'hostname=test_tunnel_id' {mock_he_log}")

    # RENEW also triggers an update
    external.succeed(f"truncate -s 0 {mock_he_log}")
    galleta.succeed("interface=eth2 reason=RENEW /bin/sh /etc/dhcpcd.exit-hook")
    external.wait_until_succeeds(f"test -s {mock_he_log}", timeout=10)

    # Wrong interface does not trigger an update
    external.succeed(f"truncate -s 0 {mock_he_log}")
    galleta.succeed("interface=eth1 reason=BOUND /bin/sh /etc/dhcpcd.exit-hook")
    galleta.succeed("sleep 2")
    external.fail(f"test -s {mock_he_log}")
  '';
}
