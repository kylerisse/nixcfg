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
    rev = "3d05c68d2555c4c8a9978623efd0c42b6781d353";
    sha256 = "sha256-nvyUaPRSqUCCfMhKhH33Sndo7YqG4jDlSWja4a+2emo=";
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
