{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    "aarch64-darwin" = {
      url = "https://releases.hashicorp.com/terraform/1.9.1/terraform_1.9.1_darwin_arm64.zip";
      sha256 = "6767c4302a1cf164d92091f66bd399732bff681e4ae9f60533a05fc3449d227d";
    };
    "x86_64-linux" = {
      url = "https://releases.hashicorp.com/terraform/1.9.1/terraform_1.9.1_linux_amd64.zip";
      sha256 = "c3e1dade1c81fdc5e293529e480709f047c0113ea9feb8d9f35002df09ec6a34";
    };
  };
in
stdenv.mkDerivation rec {
  tfzip = pkgs.fetchurl {
    url = cfg.${pkgs.system}.url;
    sha256 = cfg.${pkgs.system}.sha256;
  };

  src = ./.;
  pname = "terraform_1-9-1";
  version = "binary";
  vstring = "1.9.1";

  propagatedBuildInputs = with pkgs; [ unzip ];

  installPhase = ''
    mkdir -p $out/bin
    unzip $tfzip
    cp terraform $out/bin/terraform-$vstring
    chmod +x $out/bin/terraform-$vstring
  '';

  meta = with lib; {
    description = "Terraform 1.9.1 (Hashicorp binary)";
    license = licenses.bsl11;
    maintainers = [ "kylerisse" ];
  };
}
