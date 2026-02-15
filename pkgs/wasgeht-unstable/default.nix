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
    rev = "master";
    sha256 = "sha256-cNm0GabApJGHPfwVRZrGdUPpWb/rTTV8b4TF918TcCU=";
  };

  vendorHash = "sha256-u9uLLtVeb9Ldvqu+ww/3pSjGF14RKX9qgLjULKYibjE=";

  ldflags = [
    "-s"
    "-w"
  ];

  buildInputs = [
    unixtools.ping
    makeWrapper
    rrdtool
  ];

  checkPhase = ''
    go test --short --race -v ./...
  '';

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
