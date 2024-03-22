{ config, pkgs, lib, ... }:
let
  format = pkgs.formats.json { };
  cfg = config.ssh-server;
in
{
  options.ssh-server = {
    enable = lib.mkEnableOption (lib.mdDoc "SSH Server");
    listenAddresses = lib.mkOption {
      type = format.type;
      default = [
        {
          addr = "0.0.0.0";
          port = 22;
        }
      ];
      description = "Listen Addresses";
    };
  };
  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
      listenAddresses = cfg.listenAddresses;
    };
    networking.firewall.allowedTCPPorts = (lib.unique (map (x: x.port) cfg.listenAddresses));
  };
}
