{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    url = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.7.0-amd64-netinst.iso";
    sha256 = "j955z8ayCmliAPxcFSGc9tch6P6zZ+ng4zp50cto+oM=";
  };
in
stdenv.mkDerivation rec {
  iso = pkgs.fetchurl {
    url = cfg.url;
    sha256 = cfg.sha256;
  };

  src = ./.;
  pname = "debian-netinst-iso";
  version = "12.7.0";

  installPhase = ''
    mkdir -p $out/iso/
    cp $iso $out/iso/
    echo ${cfg.url} - ${cfg.sha256} > $out/iso/metadata.txt
  '';

  meta = with lib; {
    description = "Debian 12.7.0 Network Installer ";
    license = licenses.gpl2;
    maintainers = [ "kylerisse" ];
  };
}
