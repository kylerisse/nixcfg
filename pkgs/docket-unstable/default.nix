{ lib
, buildGoModule
, fetchFromGitHub
,
}:
buildGoModule rec {
  pname = "docket";
  version = "unstable";
  commit = "0705830edc161a186a850f76130c804c19e3329b";

  src = fetchFromGitHub {
    owner = "ALT-F4-LLC";
    repo = "docket";
    rev = commit;
    sha256 = "sha256-MHn0CRFt5OXJORGdu0gyzCt8qma5bD3rrpq/YlWhyTs=";
  };

  vendorHash = "sha256-vf92FTM1jtWC4NG0LmG7zPD+Q4DETY355VUlqpIOYF4=";

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
