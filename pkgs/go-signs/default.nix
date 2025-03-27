{ pkgs
, lib
, buildGoModule
, fetchFromGitHub
}:
let
  src = fetchFromGitHub {
    owner = "kylerisse";
    rev = "13aa95058f53b576c0e59186ab99f9555259d0af";
    repo = "go-signs";
    sha256 = "sha256-659R6d+QGbnIHuJLR4T8Tr/JBqaEDbxMnCjXI115R50=";
  };
in
buildGoModule rec {
  inherit src;
  pname = "go-signs";
  version = "unstable";

  sourceRoot = "${src.name}/";

  vendorHash = "sha256-8wYERVt3PIsKkarkwPu8Zy/Sdx43P6g2lz2xRfvTZ2E=";

  meta = with lib; {
    description = "go-signs API server for SoCal Linux Expo schedule info";
    homepage = "https://github.com/kylerisse/go-signs";
    maintainers = [ "kylerisse" ];
    license = licenses.mit;
  };
}
