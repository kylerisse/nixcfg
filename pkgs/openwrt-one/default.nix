{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    factory = {
      url = "https://downloads.openwrt.org/releases/24.10.0/targets/mediatek/filogic/openwrt-24.10.0-mediatek-filogic-openwrt_one-factory.ubi";
      sha256 = "sha256-hymZbQU4A+CFoU3+N8LWJj2ZH43jESZPp1C86gYi9CQ=";
    };
    sysupgrade = {
      url = "https://downloads.openwrt.org/releases/24.10.0/targets/mediatek/filogic/openwrt-24.10.0-mediatek-filogic-openwrt_one-squashfs-sysupgrade.itb";
      sha256 = "sha256-GM9q1jk82nGEpSTloIIbrOeHt1gILvtMYkibL6LkpsU=";
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
  pname = "openwrt-one";
  version = "24.10.0";

  installPhase = ''
    mkdir -p $out/images/
    cp $factoryImg $out/images/
    cp $sysupgradeImg $out/images/
    echo "factory - ${cfg.factory.url} - ${cfg.factory.sha256}" > $out/images/metadata.txt
    echo "sysupgrade - ${cfg.sysupgrade.url} - ${cfg.sysupgrade.sha256}" >> $out/images/metadata.txt
  '';

  meta = with lib; {
    description = "OpenWRT 24.10.0 OpenWRT One";
    license = licenses.gpl3;
    maintainers = [ "kylerisse" ];
  };
}
