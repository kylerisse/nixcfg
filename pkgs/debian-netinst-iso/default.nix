{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    version = "12.10.0";
    url = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-${cfg.version}-amd64-netinst.iso";
    sha256 = "sha256-7o2FeRKJd9fcOdSPQ67Fqwa38J4fQKnZjyqdFJIhcEo=";
  };
in
stdenv.mkDerivation rec {
  iso = pkgs.fetchurl {
    url = cfg.url;
    sha256 = cfg.sha256;
  };

  src = ./.;
  pname = "debian-netinst-iso";
  version = cfg.version;

  installPhase = ''
    mkdir -p $out/iso/
    cp $iso $out/iso/
    echo ${cfg.url} - ${cfg.sha256} > $out/iso/metadata.txt
  '';

  meta = with lib; {
    description = "Debian ${cfg.version} Network Installer ";
    license = licenses.gpl2;
    maintainers = [ "kylerisse" ];
  };
}
