{ lib
, buildGoModule
,
}:
buildGoModule {
  pname = "andiamo";
  version = "0.1.1";

  src = ../../tools/andiamo;

  # stdlib only, no vendored dependencies
  vendorHash = null;

  ldflags = [
    "-s"
    "-w"
  ];

  checkPhase = ''
    go test --short --race -v ./...
  '';

  meta = with lib; {
    description = "let's go — fleet deployment tool for this flake";
    homepage = "https://github.com/kylerisse/nixcfg";
    license = licenses.mit;
    maintainers = [ "kylerisse" ];
    mainProgram = "andiamo";
  };
}
