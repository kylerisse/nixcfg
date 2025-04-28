{ config
, pkgs
, lib
, inputs
, ...
}:
let
  cfg = config.scale-simulator;

  externalPkgs = inputs.go-signs.packages.${pkgs.system};
in
{
  options.scale-simulator = {
    enable = lib.mkEnableOption "SCaLE simulator service";

    package = lib.mkOption {
      type = lib.types.package;
      default = externalPkgs.scale-simulator;
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 2018;
    };
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      services.scale-simulator = {
        description = "SCaLE simulator service";
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          DynamicUser = true;
          StateDirectory = "scale-simulator";
          ExecStart = "${lib.getExe cfg.package} --db=/var/lib/scale-simulator/simulator.db --port=${builtins.toString cfg.port}";
          ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR1 $MAINPID";
        };
      };
    };
  };
}
