{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    factory = {
      url = "https://downloads.openwrt.org/releases/23.05.5/targets/ath79/generic/openwrt-23.05.5-ath79-generic-tplink_archer-a7-v5-squashfs-factory.bin";
      sha256 = "5312bd7be66e83209acf27540a5e3846343c8d9dff271cba5186443b2d3df38f";
    };
    sysupgrade = {
      url = "https://downloads.openwrt.org/releases/23.05.5/targets/ath79/generic/openwrt-23.05.5-ath79-generic-tplink_archer-a7-v5-squashfs-sysupgrade.bin";
      sha256 = "7740d3ab17ec20347dd9d9319cc307ca85e6bbcfb8ed4ca9c7fce82307555a59";
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
  version = "23.05.5";

  installPhase = ''
    mkdir -p $out/images/
    cp $factoryImg $out/images/
    cp $sysupgradeImg $out/images/
    echo "factory - ${cfg.factory.url} - ${cfg.factory.sha256}" > $out/images/metadata.txt
    echo "sysupgrade - ${cfg.sysupgrade.url} - ${cfg.sysupgrade.sha256}" >> $out/images/metadata.txt
  '';

  meta = with lib; {
    description = "OpenWRT 23.05.5 Archer A7 v5";
    license = licenses.gpl3;
    maintainers = [ "kylerisse" ];
  };
}
