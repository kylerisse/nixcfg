{ stdenv
, lib
, python3
, gtk3
, glib
, xapp
, gobject-introspection
, wrapGAppsHook3
,
}:
let
  pythonEnv = python3.withPackages (ps: [ ps.pygobject3 ]);
in
stdenv.mkDerivation {
  pname = "sdl-ss-inhibitors-tray";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    wrapGAppsHook3
    gobject-introspection
  ];

  buildInputs = [
    pythonEnv
    gtk3
    glib
    xapp
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 sdl-ss-inhibitors-tray.py $out/bin/sdl-ss-inhibitors-tray
    sed -i "1c#!${pythonEnv}/bin/python3" $out/bin/sdl-ss-inhibitors-tray

    runHook postInstall
  '';

  meta = with lib; {
    description = "Tray applet that monitors session-manager inhibitors and flags stale ones";
    license = licenses.mit;
    maintainers = [ "kylerisse" ];
    mainProgram = "sdl-ss-inhibitors-tray";
    platforms = platforms.linux;
  };
}
