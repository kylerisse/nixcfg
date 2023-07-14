{ pkgs
, lib
, stdenv
, fetchurl
}:
let
  cfg = {
    "aarch64-darwin" = {
      url = "https://releases.hashicorp.com/terraform/1.5.2/terraform_1.5.2_darwin_arm64.zip";
      sha256 = "75c5632f221adbba38d569bdaeb6c3cb90b7f82e26b01e39b3b7e1c16bb0e4d4";
    };
    "x86_64-linux" = {
      url = "https://releases.hashicorp.com/terraform/1.5.2/terraform_1.5.2_linux_amd64.zip";
      sha256 = "781ffe0c8888d35b3f5bd0481e951cebe9964b9cfcb27e352f22687975401bcd";
    };
  };
in
stdenv.mkDerivation rec {
  tfzip = pkgs.fetchurl {
    url = cfg.${pkgs.system}.url;
    sha256 = cfg.${pkgs.system}.sha256;
  };

  src = ./.;
  pname = "terraform_1-5-2";
  version = "binary";
  vstring = "1.5.2";

  propagatedBuildInputs = with pkgs; [ unzip ];

  installPhase = ''
    mkdir -p $out/bin
    unzip $tfzip
    cp terraform $out/bin/terraform-$vstring
    chmod +x $out/bin/terraform-$vstring
  '';

  meta = with lib; {
    description = "Terraform 1.5.2 (Hashicorp binary)";
    license = licenses.mpl20;
    maintainers = [ "kylerisse" ];
  };
}
