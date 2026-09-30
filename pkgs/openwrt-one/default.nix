{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  version = "25.12.5";
  baseUrl = "https://downloads.openwrt.org/releases/${version}/targets/mediatek/filogic";
  cfg = {
    factory = {
      url = "${baseUrl}/openwrt-${version}-mediatek-filogic-openwrt_one-factory.ubi";
      sha256 = "sha256-77SnCARl1wwREZA2D9LGf+BRiFMtnPsC6p0Snv8ERPo=";
    };
    sysupgrade = {
      url = "${baseUrl}/openwrt-${version}-mediatek-filogic-openwrt_one-squashfs-sysupgrade.itb";
      sha256 = "sha256-dx+6ymzeIwrHFnYwZ01RzbQ3DTa8Spsi426xlpETd5w=";
    };
  };
in
stdenv.mkDerivation rec {
  inherit version;

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

  installPhase = ''
    mkdir -p $out/images/
    cp $factoryImg $out/images/
    cp $sysupgradeImg $out/images/
    echo "factory - ${cfg.factory.url} - ${cfg.factory.sha256}" > $out/images/metadata.txt
    echo "sysupgrade - ${cfg.sysupgrade.url} - ${cfg.sysupgrade.sha256}" >> $out/images/metadata.txt
  '';

  meta = with lib; {
    description = "OpenWRT ${version} OpenWRT One";
    license = licenses.gpl3;
    maintainers = [ "kylerisse" ];
  };
}
