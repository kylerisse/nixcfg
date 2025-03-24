{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    version = "6.3.2";
    url = "https://deb.parrot.sh/parrot/iso/${cfg.version}/Parrot-htb-${cfg.version}_amd64.iso";
    sha256 = "sha256-7oRItid4tcdAkjY20IuTQfNPc8RA8TYiYqZkafTKhUs=";
  };
in
stdenv.mkDerivation rec {
  iso = pkgs.fetchurl {
    url = cfg.url;
    sha256 = cfg.sha256;
  };

  src = ./.;
  pname = "ParrotOS_HTB_ISO";
  version = cfg.version;

  installPhase = ''
    mkdir -p $out/iso/
    cp $iso $out/iso/
    echo ${cfg.url} - ${cfg.sha256} > $out/iso/metadata.txt
  '';

  meta = with lib; {
    description = "Parrot OS ${cfg.version} Hack The Box Edition ISO";
    license = licenses.gpl2;
    maintainers = [ "kylerisse" ];
  };
}
