{ config, pkgs, lib, ... }:
let
  cfg = config.mynixcfg.he-tunnel-update;
  inherit (lib.modules) mkIf;
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib) types;
in
{
  options.mynixcfg.he-tunnel-update = {
    enable = mkEnableOption "Hurricane Electric tunnel endpoint updater";
    credentialsFile = mkOption {
      type = types.str;
      default = "/etc/he-tunnel/credentials";
      description = ''
        Path to file containing three lines:
          tunnel_id
          username
          update_key
      '';
    };
    interval = mkOption {
      type = types.str;
      default = "1h";
      description = "How often to check and update the tunnel endpoint (safety net)";
    };
    wanInterface = mkOption {
      type = types.str;
      default = "enp1s0";
      description = "WAN interface to watch for DHCP changes";
    };
    updateUrl = mkOption {
      type = types.str;
      default = "https://ipv4.tunnelbroker.net/nic/update";
      description = "Tunnel endpoint update URL";
    };
  };

  config =
    let
      script = pkgs.writeShellScript "he-tunnel-update" ''
        set -euo pipefail

        { read -r TUNNEL_ID; read -r USERNAME; read -r UPDATE_KEY; } < "$CREDENTIALS_DIRECTORY/he-creds"

        RESPONSE=$(${pkgs.curl}/bin/curl -4 -sf \
          -u "$USERNAME:$UPDATE_KEY" \
          "${cfg.updateUrl}?hostname=$TUNNEL_ID")

        echo "$(date -Iseconds) $RESPONSE"
      '';
    in
    mkIf cfg.enable {
      systemd.services.he-tunnel-update = {
        description = "Update Hurricane Electric tunnel endpoint";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${script}";
          Type = "oneshot";
          DynamicUser = true;
          LoadCredential = "he-creds:${cfg.credentialsFile}";
        };
      };

      systemd.timers.he-tunnel-update = {
        description = "Periodically update HE tunnel endpoint";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = cfg.interval;
          Unit = "he-tunnel-update.service";
        };
      };

      networking.dhcpcd.runHook = ''
        if [ "$interface" = "${cfg.wanInterface}" ] && { [ "$reason" = "BOUND" ] || [ "$reason" = "RENEW" ] || [ "$reason" = "REBIND" ]; }; then
          /run/current-system/sw/bin/systemctl start he-tunnel-update.service || true
        fi
      '';

      systemd.tmpfiles.rules = [
        "d /etc/he-tunnel 0700 root root"
      ];
    };
}
