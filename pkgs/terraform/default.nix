{ pkgs, lib, stdenv }:
let
  versions = {
    "1.8.2" = {
      sha256 = "f871f4c91eafec6e6e88253dc3cc0b6a21d63fa56fee5ee1629f3ce68a605873";
    };
    "1.8.3" = {
      sha256 = "2622426fd6e8483db6d62605f52ea6eddb0e88a09e8cea1c24b9310879490227";
    };
    "1.9.1" = {
      sha256 = "6767c4302a1cf164d92091f66bd399732bff681e4ae9f60533a05fc3449d227d";
    };
    "1.9.6" = {
      sha256 = "f106632f6f7df76587d7a194b1ceb40b029567861ee8af6baade3cdebce475f7";
    };
  };

  mkTerraform = version: { sha256 }:
    let
      vstring = builtins.replaceStrings [ "." ] [ "-" ] version;
    in
    stdenv.mkDerivation {
      pname = "terraform_${vstring}";
      version = "binary";

      src = pkgs.fetchurl {
        url = "https://releases.hashicorp.com/terraform/${version}/terraform_${version}_darwin_arm64.zip";
        inherit sha256;
      };

      sourceRoot = ".";

      nativeBuildInputs = with pkgs; [ unzip ];

      installPhase = ''
        mkdir -p $out/bin
        cp terraform $out/bin/terraform-${version}
        chmod +x $out/bin/terraform-${version}
      '';

      meta = with lib; {
        description = "Terraform ${version} (Hashicorp binary)";
        license = licenses.bsl11;
        maintainers = [ "kylerisse" ];
        platforms = [ "aarch64-darwin" ];
      };
    };
in
lib.mapAttrs mkTerraform versions
