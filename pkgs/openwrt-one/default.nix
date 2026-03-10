{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    factory = {
      url = "https://downloads.openwrt.org/releases/25.12.0/targets/mediatek/filogic/openwrt-25.12.0-mediatek-filogic-openwrt_one-factory.ubi";
      sha256 = "sha256-AEjLp3dPHj2SjMh7JxtYxuRI9xPk5jZZ/Bq62n9Gock=";
    };
    sysupgrade = {
      url = "https://downloads.openwrt.org/releases/25.12.0/targets/mediatek/filogic/openwrt-25.12.0-mediatek-filogic-openwrt_one-squashfs-sysupgrade.itb";
      sha256 = "sha256-+VXpZ7OdZOhGwaTbrThkCXPmP08IqFk7PzPD8b8GVqs=";
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
  version = "25.12.0";

  installPhase = ''
    mkdir -p $out/images/
    cp $factoryImg $out/images/
    cp $sysupgradeImg $out/images/
    echo "factory - ${cfg.factory.url} - ${cfg.factory.sha256}" > $out/images/metadata.txt
    echo "sysupgrade - ${cfg.sysupgrade.url} - ${cfg.sysupgrade.sha256}" >> $out/images/metadata.txt
  '';

  meta = with lib; {
    description = "OpenWRT 25.12.0 OpenWRT One";
    license = licenses.gpl3;
    maintainers = [ "kylerisse" ];
  };
}
