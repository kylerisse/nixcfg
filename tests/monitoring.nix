{ lib, network, inputs, nixpkgs, allModule }:
{
  name = "monitoring";

  nodes = {
    server = { pkgs, ... }: {
      imports = [
        allModule
      ];

      _module.args = { inherit network inputs nixpkgs; };

      mynixcfg.nix-common.enable = lib.mkForce false;

      mynixcfg.mimir.enable = true;
      mynixcfg.tempo.enable = true;
      mynixcfg.grafana = {
        enable = true;
        domain = "localhost";
        secretKeyFile = "${pkgs.writeText "grafana-secret" "test-secret-key-for-vm-test"}";
      };
      mynixcfg.alloy = {
        enable = true;
        remoteWriteUrl = "http://127.0.0.1:3200/api/v1/push";
      };

      networking.firewall.allowedTCPPorts = [ 3000 3200 4410 ];

      virtualisation = {
        memorySize = 1024;
      };
    };

    agent = { pkgs, ... }: {
      imports = [
        allModule
      ];

      _module.args = { inherit network inputs nixpkgs; };

      mynixcfg.nix-common.enable = lib.mkForce false;

      mynixcfg.alloy = {
        enable = true;
        remoteWriteUrl = "http://server:3200/api/v1/push";
      };
    };
  };

  testScript = ''
    start_all()

    # Wait for core services on server
    server.wait_for_unit("mimir.service")
    server.wait_for_unit("tempo.service")
    server.wait_for_unit("grafana.service")
    server.wait_for_unit("alloy.service")

    # Wait for agent
    agent.wait_for_unit("alloy.service")

    # Mimir is ready
    server.wait_until_succeeds("curl -sf http://127.0.0.1:3200/ready", timeout=60)

    # Tempo is ready
    server.wait_until_succeeds("curl -sf http://127.0.0.1:4410/ready", timeout=60)

    # Grafana is responding
    server.wait_until_succeeds("curl -sf http://127.0.0.1:3000/api/health", timeout=30)

    # Grafana has the Mimir datasource provisioned (default admin:admin creds)
    server.succeed("curl -sf -u admin:admin http://127.0.0.1:3000/api/datasources | grep Mimir")

    # Grafana has the Tempo datasource provisioned
    server.succeed("curl -sf -u admin:admin http://127.0.0.1:3000/api/datasources | grep Tempo")

    # Wait for metrics to flow through, then query Mimir for the up metric
    server.wait_until_succeeds(
        "curl -sf 'http://127.0.0.1:3200/prometheus/api/v1/query?query=up' | grep '\"value\"'",
        timeout=120,
    )

    # Verify the server's own metrics are pushed with host=server
    server.wait_until_succeeds(
        "curl -sf 'http://127.0.0.1:3200/prometheus/api/v1/query?query=up' | grep '\"host\":\"server\"'",
        timeout=60,
    )

    # Verify the agent pushed its own metrics (host=agent), not just scraped by server
    server.wait_until_succeeds(
        "curl -sf 'http://127.0.0.1:3200/prometheus/api/v1/query?query=up' | grep '\"host\":\"agent\"'",
        timeout=60,
    )

    # Push a test trace to Tempo via OTLP HTTP and verify it can be queried back
    server.succeed(
        """curl -sf -X POST http://127.0.0.1:4418/v1/traces \
           -H 'Content-Type: application/json' \
           -d '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"test-service"}}]},"scopeSpans":[{"spans":[{"traceId":"01020304050607080102030405060708","spanId":"0102030405060708","name":"test-span","kind":1,"startTimeUnixNano":"1700000000000000000","endTimeUnixNano":"1700000001000000000","status":{}}]}]}]}'"""
    )

    # Query Tempo for the trace by ID
    server.wait_until_succeeds(
        "curl -sf http://127.0.0.1:4410/api/traces/01020304050607080102030405060708 | grep test-span",
        timeout=30,
    )

    # Verify Grafana can query the trace through the Tempo datasource
    server.wait_until_succeeds(
        "curl -sf -u admin:admin 'http://127.0.0.1:3000/api/datasources/proxy/uid/tempo/api/traces/01020304050607080102030405060708' | grep test-span",
        timeout=30,
    )
  '';
}
