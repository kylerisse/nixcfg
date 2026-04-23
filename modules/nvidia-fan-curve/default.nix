{ config, pkgs, lib, ... }:
let
  cfg = config.mynixcfg.nvidia-fan-curve;

  nvidiaPackage = config.hardware.nvidia.package;

  script = pkgs.writeShellScript "nvidia-fan-curve" ''
    CURVE_TEMPS=(${lib.concatMapStringsSep " " toString cfg.curve.temps})
    CURVE_SPEEDS=(${lib.concatMapStringsSep " " toString cfg.curve.speeds})
    INTERVAL=${toString cfg.interval}
    DISPLAY="${cfg.display}"

    NVIDIA_SETTINGS="${nvidiaPackage.settings}/bin/nvidia-settings"
    NVIDIA_SMI="${nvidiaPackage.bin}/bin/nvidia-smi"

    get_target_speed() {
      local temp=$1
      local len=''${#CURVE_TEMPS[@]}

      if (( temp <= CURVE_TEMPS[0] )); then
        echo "''${CURVE_SPEEDS[0]}"
        return
      fi

      if (( temp >= CURVE_TEMPS[len-1] )); then
        echo "''${CURVE_SPEEDS[len-1]}"
        return
      fi

      for (( i=1; i<len; i++ )); do
        if (( temp <= CURVE_TEMPS[i] )); then
          local t0=''${CURVE_TEMPS[i-1]}
          local t1=''${CURVE_TEMPS[i]}
          local s0=''${CURVE_SPEEDS[i-1]}
          local s1=''${CURVE_SPEEDS[i]}
          local speed=$(( s0 + (temp - t0) * (s1 - s0) / (t1 - t0) ))
          echo "$speed"
          return
        fi
      done
    }

    LAST_SPEED=-1
    MANUAL_CONTROL=0

    while true; do
      temp=$($NVIDIA_SMI --query-gpu=temperature.gpu --format=csv,noheader,nounits)
      speed=$(get_target_speed "$temp")

      if (( temp < 45 )); then
        # below 45C, disable manual control and let GPU handle fans (fans off)
        if (( MANUAL_CONTROL == 1 )); then
          $NVIDIA_SETTINGS -c "$DISPLAY" -a "[gpu:0]/GPUFanControlState=0" > /dev/null 2>&1
          MANUAL_CONTROL=0
          LAST_SPEED=-1
        fi
      else
        # at or above 45C, enable manual control and set fan speed
        if (( MANUAL_CONTROL == 0 )); then
          $NVIDIA_SETTINGS -c "$DISPLAY" -a "[gpu:0]/GPUFanControlState=1" > /dev/null 2>&1
          MANUAL_CONTROL=1
        fi
        if (( speed != LAST_SPEED )); then
          $NVIDIA_SETTINGS -c "$DISPLAY" -a "[fan:0]/GPUTargetFanSpeed=$speed" > /dev/null 2>&1
          $NVIDIA_SETTINGS -c "$DISPLAY" -a "[fan:1]/GPUTargetFanSpeed=$speed" > /dev/null 2>&1
          LAST_SPEED=$speed
        fi
      fi

      fan0_rpm=$($NVIDIA_SETTINGS -c "$DISPLAY" -t -q "[fan:0]/GPUCurrentFanSpeedRPM" 2>/dev/null)
      fan1_rpm=$($NVIDIA_SETTINGS -c "$DISPLAY" -t -q "[fan:1]/GPUCurrentFanSpeedRPM" 2>/dev/null)
      if (( MANUAL_CONTROL == 0 )); then
        log_speed=0
      else
        log_speed=$speed
      fi
      echo "temp=''${temp}C target=''${log_speed}% fan0=''${fan0_rpm}rpm fan1=''${fan1_rpm}rpm manual=''${MANUAL_CONTROL}"

      sleep "$INTERVAL"
    done
  '';
in
{
  options.mynixcfg.nvidia-fan-curve = {
    enable = lib.mkEnableOption "NVIDIA GPU dynamic fan curve";

    display = lib.mkOption {
      type = lib.types.str;
      default = ":0";
      description = "X display to use for nvidia-settings";
    };

    interval = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Seconds between temperature checks";
    };

    curve = {
      temps = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ 40 45 80 ];
        description = "Temperature thresholds in Celsius (must be same length as speeds)";
      };

      speeds = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [ 30 45 100 ];
        description = "Fan speed percentages corresponding to each temperature threshold";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (builtins.length cfg.curve.temps) == (builtins.length cfg.curve.speeds);
        message = "mynixcfg.nvidia-fan-curve: curve.temps and curve.speeds must have the same length";
      }
    ];

    systemd.services.nvidia-fan-curve = {
      description = "NVIDIA GPU dynamic fan control";
      after = [ "display-manager.service" ];
      requires = [ "display-manager.service" ];
      environment = {
        XAUTHORITY = "/var/run/lightdm/root/:0";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${script}";
        Restart = "on-failure";
        RestartSec = 5;
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
