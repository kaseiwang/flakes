{
  source,
  lib,
  stdenv,
  cmake,
  makeWrapper,
  curl,
  which,
}:
stdenv.mkDerivation (finalAttrs: {
  inherit (source) pname src;
  version = lib.removePrefix "v" source.version;

  nativeBuildInputs = [
    cmake
    makeWrapper
  ];
  strictDeps = true;

  env.RELEASE_VERSION = finalAttrs.version;
  cmakeFlags = [
    "-DCMAKE_INSTALL_SYSCONFDIR=/etc"
    "-DENABLE_AGGRESSIVE_OPT=OFF"
  ];

  # Releases include the generated Web UI and verify it against the frontend
  # sources in CI, so building the daemon does not need Node.js or pnpm.
  installPhase = ''
    runHook preInstall
    install -Dm755 rtp2httpd "$out/bin/rtp2httpd"
    install -Dm644 ../rtp2httpd.conf "$out/share/doc/rtp2httpd/rtp2httpd.conf"
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/rtp2httpd" \
      --prefix PATH : ${
        lib.makeBinPath [
          curl
          which
        ]
      }
  '';

  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/rtp2httpd" --help | grep -F "Version ${finalAttrs.version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Multicast RTP/UDP and RTSP to HTTP streaming server with a web player";
    homepage = "https://github.com/stackia/rtp2httpd";
    license = lib.licenses.gpl2Only;
    mainProgram = "rtp2httpd";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
