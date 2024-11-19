{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    factory = {
      url = "https://downloads.openwrt.org/releases/23.05.5/targets/ath79/generic/openwrt-23.05.5-ath79-generic-tplink_archer-c7-v2-squashfs-factory-us.bin";
      sha256 = "cdd93b7decaed7efbea599bc9a8d4a99f1f1f92718b2be52c08237ceeb5332ca";
    };
    sysupgrade = {
      url = "https://downloads.openwrt.org/releases/23.05.5/targets/ath79/generic/openwrt-23.05.5-ath79-generic-tplink_archer-c7-v2-squashfs-sysupgrade.bin";
      sha256 = "4e22524a1a59090d8f316ad48b13a61ab46f748d9b6215ec0926f9747369fcd5";
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
  pname = "openwrt-archer-c7-v2";
  version = "23.05.5";

  installPhase = ''
    mkdir -p $out/images/
    cp $factoryImg $out/images/
    cp $sysupgradeImg $out/images/
    echo "factory - ${cfg.factory.url} - ${cfg.factory.sha256}" > $out/images/metadata.txt
    echo "sysupgrade - ${cfg.sysupgrade.url} - ${cfg.sysupgrade.sha256}" >> $out/images/metadata.txt
  '';

  meta = with lib; {
    description = "OpenWRT 23.05.5 Archer C7 v2";
    license = licenses.gpl3;
    maintainers = [ "kylerisse" ];
  };
}
