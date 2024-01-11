{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    "aarch64-darwin" = {
      url = "https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_darwin_arm64.zip";
      sha256 = "01e608fc04cf54869db687a212d60f3dc3d5c828298514857f9e29f8ac1354a9";
    };
    "x86_64-linux" = {
      url = "https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip";
      sha256 = "d117883fd98b960c5d0f012b0d4b21801e1aea985e26949c2d1ebb39af074f00";
    };
  };
in
stdenv.mkDerivation rec {
  tfzip = pkgs.fetchurl {
    url = cfg.${pkgs.system}.url;
    sha256 = cfg.${pkgs.system}.sha256;
  };

  src = ./.;
  pname = "terraform_1-6-6";
  version = "binary";
  vstring = "1.6.6";

  propagatedBuildInputs = with pkgs; [ unzip ];

  installPhase = ''
    mkdir -p $out/bin
    unzip $tfzip
    cp terraform $out/bin/terraform-$vstring
    chmod +x $out/bin/terraform-$vstring
  '';

  meta = with lib; {
    description = "Terraform 1.6.6 (Hashicorp binary)";
    license = licenses.bsl11;
    maintainers = [ "kylerisse" ];
  };
}
