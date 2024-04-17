{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    "aarch64-darwin" = {
      url = "https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_darwin_arm64.zip";
      sha256 = "99c4d4feafb0183af2f7fbe07beeea6f83e5f5a29ae29fee3168b6810e37ff98";
    };
    "x86_64-linux" = {
      url = "https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip";
      sha256 = "3ff056b5e8259003f67fd0f0ed7229499cfb0b41f3ff55cc184088589994f7a5";
    };
  };
in
stdenv.mkDerivation rec {
  tfzip = pkgs.fetchurl {
    url = cfg.${pkgs.system}.url;
    sha256 = cfg.${pkgs.system}.sha256;
  };

  src = ./.;
  pname = "terraform_1-7-5";
  version = "binary";
  vstring = "1.7.5";

  propagatedBuildInputs = with pkgs; [ unzip ];

  installPhase = ''
    mkdir -p $out/bin
    unzip $tfzip
    cp terraform $out/bin/terraform-$vstring
    chmod +x $out/bin/terraform-$vstring
  '';

  meta = with lib; {
    description = "Terraform 1.7.5 (Hashicorp binary)";
    license = licenses.bsl11;
    maintainers = [ "kylerisse" ];
  };
}
