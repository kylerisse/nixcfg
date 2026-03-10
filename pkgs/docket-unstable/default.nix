{ lib
, buildGoModule
, fetchFromGitHub
,
}:
buildGoModule rec {
  pname = "docket";
  version = "unstable";

  commit = "a2ccaa209372514fbb51a3c336188321d0132ad6";

  src = fetchFromGitHub {
    owner = "ALT-F4-LLC";
    repo = "docket";
    rev = commit;
    sha256 = "sha256-BNTxQfPdfMmIfruyreCtmYS84oZxGgQ1WfnRN87g0WM=";
  };

  vendorHash = "sha256-HIM1iaBLDy1hPOnPe+25RM15YwQRrCFubiuzGLFnvbM=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/ALT-F4-LLC/docket/internal/cli.commit=${commit}"
    "-X github.com/ALT-F4-LLC/docket/internal/cli.buildDate=1970-01-01T00:00:00Z"
  ];

  meta = with lib; {
    description = "Issue tracking for ai and humans";
    homepage = "https://github.com/ALT-F4-LLC/docket";
    license = licenses.asl20;
    maintainers = [ "kylerisse" ];
    mainProgram = "docket";
  };
}
