{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    "aarch64-darwin" = {
      url = "https://releases.hashicorp.com/terraform/1.4.2/terraform_1.4.2_darwin_arm64.zip";
      sha256 = "af8ff7576c8fc41496fdf97e9199b00d8d81729a6a0e821eaf4dfd08aa763540";
    };
    "x86_64-linux" = {
      url = "https://releases.hashicorp.com/terraform/1.4.2/terraform_1.4.2_linux_amd64.zip";
      sha256 = "9f3ca33d04f5335472829d1df7785115b60176d610ae6f1583343b0a2221a931";
    };
  };
in
stdenv.mkDerivation rec {
  tfzip = pkgs.fetchurl {
    url = cfg.${pkgs.system}.url;
    sha256 = cfg.${pkgs.system}.sha256;
  };

  src = ./.;
  pname = "terraform_1-4-2";
  version = "1.4.2";

  propagatedBuildInputs = with pkgs; [ unzip ];

  installPhase = ''
    mkdir -p $out/bin
    unzip $tfzip
    cp terraform $out/bin/terraform-$version
    chmod +x $out/bin/terraform-$version
  '';
  ## TODO: add fish completions
  ## TODO: fix out name of terraform_1-4-2-1.4.2

  meta = with lib; {
    description = "Terraform 1.4.2 (Hashicorp binary)";
    license = licenses.mpl20;
    maintainers = [ "kylerisse" ];
  };
}
