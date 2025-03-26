{ pkgs
, lib
, buildGoModule
, fetchFromGitHub
}:
let
  src = fetchFromGitHub {
    owner = "kylerisse";
    rev = "25f045c320ac0f47db68e24a3bb990d53f343c1a";
    repo = "go-signs";
    sha256 = "sha256-DwrzyoPICAkLB0zrnyn+ox/ApWpSpP5IoB+idbXg4qI=";
  };
in
buildGoModule rec {
  inherit src;
  pname = "go-signs";
  version = "unstable";

  sourceRoot = "${src.name}/";

  vendorHash = "sha256-v+30UyKGa4BYOO3y77gOTyvQljz0W24v1+2zpPxstR4=";

  meta = with lib; {
    description = "go-signs API server for SoCal Linux Expo schedule info";
    homepage = "https://github.com/kylerisse/go-signs";
    maintainers = [ "kylerisse" ];
    license = licenses.mit;
  };
}
