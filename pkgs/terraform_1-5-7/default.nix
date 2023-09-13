{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    "aarch64-darwin" = {
      url = "https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_darwin_arm64.zip";
      sha256 = "db7c33eb1a446b73a443e2c55b532845f7b70cd56100bec4c96f15cfab5f50cb";
    };
    "x86_64-linux" = {
      url = "https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip";
      sha256 = "c0ed7bc32ee52ae255af9982c8c88a7a4c610485cf1d55feeb037eab75fa082c";
    };
  };
in
stdenv.mkDerivation rec {
  tfzip = pkgs.fetchurl {
    url = cfg.${pkgs.system}.url;
    sha256 = cfg.${pkgs.system}.sha256;
  };

  src = ./.;
  pname = "terraform_1-5-7";
  version = "binary";
  vstring = "1.5.7";

  propagatedBuildInputs = with pkgs; [ unzip ];

  installPhase = ''
    mkdir -p $out/bin
    unzip $tfzip
    cp terraform $out/bin/terraform-$vstring
    chmod +x $out/bin/terraform-$vstring
  '';

  meta = with lib; {
    description = "Terraform 1.5.7 (Hashicorp binary)";
    license = licenses.bsl11;
    maintainers = [ "kylerisse" ];
  };
}
