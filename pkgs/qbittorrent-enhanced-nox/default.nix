{
  source,
  lib,
  pkgs,
  stdenv,
  fetchFromGitHub,
  boost,
  cmake,
  trackerSearch ? true,
  webuiSupport ? true,
}:

let
  qtVersion = "6";
in
stdenv.mkDerivation rec {
  inherit (source) pname version src;

  nativeBuildInputs = with pkgs; [
    cmake
    ninja
    wrapGAppsHook
    qt6.wrapQtAppsHook
  ];

  buildInputs =
    with pkgs;
    [
      boost
      libtorrent-rasterbar
      qt6.qtbase
      qt6.qtsvg
      qt6.qttools
    ]
    ++ lib.optionals stdenv.isDarwin [
      Cocoa
    ]
    ++ lib.optionals trackerSearch [
      python3
    ];

  cmakeFlags =
    lib.optionals (qtVersion == "6") [
      "-DQT6=ON"
      "-DGUI=OFF"
      "-DSYSTEMD=ON"
      "-DSYSTEMD_SERVICES_INSTALL_DIR=${placeholder "out"}/lib/systemd/system"
    ]
    ++ lib.optionals (!webuiSupport) [
      "-DWEBUI=OFF"
    ];

  qtWrapperArgs = lib.optionals trackerSearch [
    "--prefix PATH : ${lib.makeBinPath [ pkgs.python3 ]}"
  ];

  dontWrapGApps = true;

  postInstall = lib.optionalString stdenv.isDarwin ''
    APP_NAME=qbittorrent-nox"}
    mkdir -p $out/{Applications,bin}
    cp -R $APP_NAME.app $out/Applications
    makeWrapper $out/{Applications/$APP_NAME.app/Contents/MacOS,bin}/$APP_NAME
  '';

  preFixup = ''
    qtWrapperArgs+=("''${gappsWrapperArgs[@]}")
  '';

  meta = with lib; {
    description = "[Unofficial] qBittorrent Enhanced, based on qBittorrent";
    homepage = "https://github.com/c0re100/qBittorrent-Enhanced-Edition";
    license = licenses.gpl2Plus;
    platforms = platforms.unix;
  };
}
