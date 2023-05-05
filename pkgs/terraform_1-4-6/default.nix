{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    "aarch64-darwin" = {
      url = "https://releases.hashicorp.com/terraform/1.4.6/terraform_1.4.6_darwin_arm64.zip";
      sha256 = "30a2f87298ff9f299452119bd14afaa8d5b000c572f62fa64baf432e35d9dec1";
    };
    "x86_64-linux" = {
      url = "https://releases.hashicorp.com/terraform/1.4.6/terraform_1.4.6_linux_amd64.zip";
      sha256 = "e079db1a8945e39b1f8ba4e513946b3ab9f32bd5a2bdf19b9b186d22c5a3d53b";
    };
  };
in
stdenv.mkDerivation rec {
  tfzip = pkgs.fetchurl {
    url = cfg.${pkgs.system}.url;
    sha256 = cfg.${pkgs.system}.sha256;
  };

  src = ./.;
  pname = "terraform_1-4-6";
  version = "binary";
  vstring = "1.4.6";

  propagatedBuildInputs = with pkgs; [ unzip ];

  installPhase = ''
    mkdir -p $out/bin
    unzip $tfzip
    cp terraform $out/bin/terraform-$vstring
    chmod +x $out/bin/terraform-$vstring
  '';

  meta = with lib; {
    description = "Terraform 1.4.6 (Hashicorp binary)";
    license = licenses.mpl20;
    maintainers = [ "kylerisse" ];
  };
}
