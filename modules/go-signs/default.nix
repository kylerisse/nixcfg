{ config
, pkgs
, lib
, inputs
, ...
}:
let
  cfg = config.go-signs;

  externalPkgs = inputs.go-signs.packages.${pkgs.system};
in
{
  options.go-signs = {
    enable = lib.mkEnableOption "SCaLE simulator service";

    package = lib.mkOption {
      type = lib.types.package;
      default = externalPkgs.go-signs;
    };

    port = lib.mkOption {
      type = lib.types.int;
      default = 2017;
    };

    refreshInterval = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "schedule refresh interval in minutes";
    };

    xmlEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://www.socallinuxexpo.org/scale/22x/sign.xml";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      services.go-signs = {
        description = "SCaLE simulator service";
        requires = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          DynamicUser = true;
          ExecStart = "${lib.getExe cfg.package} --xml=${cfg.xmlEndpoint} --refresh=${builtins.toString cfg.refreshInterval} --port=${builtins.toString cfg.port}";
          ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR1 $MAINPID";
        };
      };
    };
  };
}
