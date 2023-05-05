{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    "aarch64-darwin" = {
      url = "https://releases.hashicorp.com/terraform/1.3.9/terraform_1.3.9_darwin_arm64.zip";
      sha256 = "d8a59a794a7f99b484a07a0ed2aa6520921d146ac5a7f4b1b806dcf5c4af0525";
    };
    "x86_64-linux" = {
      url = "https://releases.hashicorp.com/terraform/1.3.9/terraform_1.3.9_linux_amd64.zip";
      sha256 = "53048fa573effdd8f2a59b726234c6f450491fe0ded6931e9f4c6e3df6eece56";
    };
  };
in
stdenv.mkDerivation rec {
  tfzip = pkgs.fetchurl {
    url = cfg.${pkgs.system}.url;
    sha256 = cfg.${pkgs.system}.sha256;
  };

  src = ./.;
  pname = "terraform_1-3-9";
  version = "binary";
  vstring = "1.3.9";

  propagatedBuildInputs = with pkgs; [ unzip ];

  installPhase = ''
    mkdir -p $out/bin
    unzip $tfzip
    cp terraform $out/bin/terraform-$vstring
    chmod +x $out/bin/terraform-$vstring
  '';

  meta = with lib; {
    description = "Terraform 1.3.9 (Hashicorp binary)";
    license = licenses.mpl20;
    maintainers = [ "kylerisse" ];
  };
}
