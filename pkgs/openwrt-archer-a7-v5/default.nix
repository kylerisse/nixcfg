{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    factory = {
      url = "https://downloads.openwrt.org/releases/24.10.0/targets/ath79/generic/openwrt-24.10.0-ath79-generic-tplink_archer-a7-v5-squashfs-factory.bin";
      sha256 = "sha256-whgNAVqqdMGZICoiXAwmtsFfgm73I1Ezf/mIGeeNIXY=";
    };
    sysupgrade = {
      url = "https://downloads.openwrt.org/releases/24.10.0/targets/ath79/generic/openwrt-24.10.0-ath79-generic-tplink_archer-a7-v5-squashfs-sysupgrade.bin";
      sha256 = "sha256-Vz4zWqIWZtpwDl2qTi9gEXE1/SqmdCyxj6r6ZCOlSFI=";
    };
  };
in
stdenv.mkDerivation rec {
  factoryImg = pkgs.fetchurl {
    url = cfg.factory.url;
    sha256 = cfg.factory.sha256;
  };
  sysupgradeImg = pkgs.fetchurl {
    url = cfg.sysupgrade.url;
    sha256 = cfg.sysupgrade.sha256;
  };

  src = ./.;
  pname = "openwrt-archer-a7-v5";
  version = "24.10.0";

  installPhase = ''
    mkdir -p $out/images/
    cp $factoryImg $out/images/
    cp $sysupgradeImg $out/images/
    echo "factory - ${cfg.factory.url} - ${cfg.factory.sha256}" > $out/images/metadata.txt
    echo "sysupgrade - ${cfg.sysupgrade.url} - ${cfg.sysupgrade.sha256}" >> $out/images/metadata.txt
  '';

  meta = with lib; {
    description = "OpenWRT 24.10.0 Archer A7 v5";
    license = licenses.gpl3;
    maintainers = [ "kylerisse" ];
  };
}
