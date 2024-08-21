{ source, stdenv, fetchFromGitHub, pkgs, lib }:

stdenv.mkDerivation rec {
  inherit (source) pname version src;

  nativeBuildInputs = [ ];
  buildInputs = [ pkgs.xorg.libX11 ];

  installPhase = ''
    make install PREFIX=$out
  '';

  meta = with lib; {
    description = "xdg-open portal for Docker containers";
    homepage = "https://github.com/kitsunyan/xdg-open-server";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
