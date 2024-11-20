{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    "aarch64-darwin" = {
      url = "https://releases.hashicorp.com/terraform/1.8.2/terraform_1.8.2_darwin_arm64.zip";
      sha256 = "f871f4c91eafec6e6e88253dc3cc0b6a21d63fa56fee5ee1629f3ce68a605873";
    };
    "x86_64-linux" = {
      url = "https://releases.hashicorp.com/terraform/1.8.2/terraform_1.8.2_linux_amd64.zip";
      sha256 = "74f3cc4151e52d94e0ecbe900552adc9b8440b4a8dc12f7fdaab2d0280788acc";
    };
  };
in
stdenv.mkDerivation rec {
  tfzip = pkgs.fetchurl {
    url = cfg.${pkgs.system}.url;
    sha256 = cfg.${pkgs.system}.sha256;
  };

  src = ./.;
  pname = "terraform_1-8-2";
  version = "binary";
  vstring = "1.8.2";

  propagatedBuildInputs = with pkgs; [ unzip ];

  installPhase = ''
    mkdir -p $out/bin
    unzip $tfzip
    cp terraform $out/bin/terraform-$vstring
    chmod +x $out/bin/terraform-$vstring
  '';

  meta = with lib; {
    description = "Terraform 1.8.2 (Hashicorp binary)";
    license = licenses.bsl11;
    maintainers = [ "kylerisse" ];
  };
}
