{ pkgs
, lib
, buildGoModule
, fetchFromGitHub
}:
let
  src = fetchFromGitHub {
    owner = "kylerisse";
    rev = "26c05190a7d80de36d1a273974176f65c7ed90e6";
    repo = "go-signs";
    sha256 = "sha256-NwJAe1hJRjS+rHqEePALlxNm9OIFvPhH0OpqUyx94Og=";
  };
in
buildGoModule rec {
  inherit src;
  pname = "go-signs";
  version = "2024-03-20";

  sourceRoot = "${src.name}/";

  vendorHash = "sha256-v+30UyKGa4BYOO3y77gOTyvQljz0W24v1+2zpPxstR4=";

  meta = with lib; {
    description = "go-signs API server for SoCal Linux Expo schedule info";
    homepage = "https://github.com/kylerisse/go-signs";
    maintainers = [ "kylerisse" ];
    license = licenses.mit;
  };
}
