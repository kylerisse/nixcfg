{ lib
, buildGoModule
, fetchFromGitHub
, makeWrapper
, unixtools
, rrdtool
,
}:
buildGoModule rec {
  pname = "wasgeht";
  version = "unstable";

  src = fetchFromGitHub {
    owner = "kylerisse";
    repo = "wasgeht";
    rev = "19f5e11ffb1defaf002e44b9d22483c77139c316";
    sha256 = "sha256-fwODrvzuBChuZwD+d5wXxIg6j5DeiAmnzLTWUz7AbfQ=";
  };

  vendorHash = "sha256-0HDZ3llIgLMxRLNei93XrcYliBzjajU6ZPllo3/IZVY=";

  ldflags = [
    "-s"
    "-w"
  ];

  buildInputs = [
    unixtools.ping
    makeWrapper
    rrdtool
  ];

  postFixup = ''
    wrapProgram $out/bin/wasgehtd --set PATH ${
      lib.makeBinPath [
        rrdtool
        unixtools.ping
      ]
    }
  '';

  meta = with lib; {
    description = "90s style monitor";
    homepage = "https://github.com/kylerisse/wasgeht";
    license = licenses.mit;
    maintainers = [ "kylerisse" ];
    mainProgram = "wasgehtd";
  };
}
