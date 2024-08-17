{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    url = "https://deb.parrot.sh/parrot/iso/6.1/Parrot-htb-6.1_amd64.iso";
    sha256 = "9ea96a8fc159682d7d03306f183db96399c79f892d7e76403d76649fd96465d7";
  };
in
stdenv.mkDerivation rec {
  iso = pkgs.fetchurl {
    url = cfg.url;
    sha256 = cfg.sha256;
  };

  src = ./.;
  pname = "ParrotOS_HTB_ISO";
  version = "6.1";

  installPhase = ''
    mkdir -p $out/iso/
    cp $iso $out/iso/
    echo ${cfg.url} - ${cfg.sha256} > $out/iso/metadata.txt
  '';

  meta = with lib; {
    description = "Parrot OS 6.1 Hack The Box Edition ISO";
    license = licenses.gpl2;
    maintainers = [ "kylerisse" ];
  };
}
