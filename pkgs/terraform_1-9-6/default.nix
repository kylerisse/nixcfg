{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    "aarch64-darwin" = {
      url = "https://releases.hashicorp.com/terraform/1.9.6/terraform_1.9.6_darwin_arm64.zip";
      sha256 = "f106632f6f7df76587d7a194b1ceb40b029567861ee8af6baade3cdebce475f7";
    };
    "x86_64-linux" = {
      url = "https://releases.hashicorp.com/terraform/1.9.6/terraform_1.9.6_linux_amd64.zip";
      sha256 = "f2c90fb1efb2ad411519d1d3ccbaee7489a60e3147f2206fdb824fb35fac9c1c";
    };
  };
in
stdenv.mkDerivation rec {
  tfzip = pkgs.fetchurl {
    url = cfg.${pkgs.system}.url;
    sha256 = cfg.${pkgs.system}.sha256;
  };

  src = ./.;
  pname = "terraform_1-9-6";
  version = "binary";
  vstring = "1.9.6";

  propagatedBuildInputs = with pkgs; [ unzip ];

  installPhase = ''
    mkdir -p $out/bin
    unzip $tfzip
    cp terraform $out/bin/terraform-$vstring
    chmod +x $out/bin/terraform-$vstring
  '';

  meta = with lib; {
    description = "Terraform 1.9.6 (Hashicorp binary)";
    license = licenses.bsl11;
    maintainers = [ "kylerisse" ];
  };
}
