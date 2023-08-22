{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    "aarch64-darwin" = {
      url = "https://releases.hashicorp.com/terraform/1.5.4/terraform_1.5.4_darwin_arm64.zip";
      sha256 = "6d68b0e1c0eab5f525f395ddaee360e2eccddff49c2af37d132e8c045b5001c5";
    };
    "x86_64-linux" = {
      url = "https://releases.hashicorp.com/terraform/1.5.4/terraform_1.5.4_linux_amd64.zip";
      sha256 = "16d9c05137ecf7f427a8cfa14ca9e7c0e73cb339f2c88ee368824ac7b4d077ea";
    };
  };
in
stdenv.mkDerivation rec {
  tfzip = pkgs.fetchurl {
    url = cfg.${pkgs.system}.url;
    sha256 = cfg.${pkgs.system}.sha256;
  };

  src = ./.;
  pname = "terraform_1-5-4";
  version = "binary";
  vstring = "1.5.4";

  propagatedBuildInputs = with pkgs; [ unzip ];

  installPhase = ''
    mkdir -p $out/bin
    unzip $tfzip
    cp terraform $out/bin/terraform-$vstring
    chmod +x $out/bin/terraform-$vstring
  '';

  meta = with lib; {
    description = "Terraform 1.5.4 (Hashicorp binary)";
    license = licenses.mpl20;
    maintainers = [ "kylerisse" ];
  };
}
