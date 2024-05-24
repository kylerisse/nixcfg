{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    "aarch64-darwin" = {
      url = "https://releases.hashicorp.com/terraform/1.8.3/terraform_1.8.3_darwin_arm64.zip";
      sha256 = "2622426fd6e8483db6d62605f52ea6eddb0e88a09e8cea1c24b9310879490227";
    };
    "x86_64-linux" = {
      url = "https://releases.hashicorp.com/terraform/1.8.3/terraform_1.8.3_linux_amd64.zip";
      sha256 = "4ff78474d0407ba6e8c3fb9ef798f2822326d121e045577f80e2a637ec33f553";
    };
  };
in
stdenv.mkDerivation rec {
  tfzip = pkgs.fetchurl {
    url = cfg.${pkgs.system}.url;
    sha256 = cfg.${pkgs.system}.sha256;
  };

  src = ./.;
  pname = "terraform_1-8-3";
  version = "binary";
  vstring = "1.8.3";

  propagatedBuildInputs = with pkgs; [ unzip ];

  installPhase = ''
    mkdir -p $out/bin
    unzip $tfzip
    cp terraform $out/bin/terraform-$vstring
    chmod +x $out/bin/terraform-$vstring
  '';

  meta = with lib; {
    description = "Terraform 1.8.3 (Hashicorp binary)";
    license = licenses.bsl11;
    maintainers = [ "kylerisse" ];
  };
}
