{
  pkgs,
  stdenv,
  fetchFromGitHub,
  ...
}:

stdenv.mkDerivation rec {
  pname = "udpxy";
  version = "1.0-25.1";

  src = fetchFromGitHub {
    owner = "pcherenkov";
    repo = "udpxy";
    rev = "cdb81068cdd5044a4d62d75188e332e535955721";
    hash = "sha256-J7NuVD+4GfPGi984WXCXG6MBAFeTM2KMzW2PzlbS0NI=";
  };

  #buildInputs = with pkgs; [ stdenv pkg-config ];

  buildPhase = ''
    sed -e 's|-Werror||' -i chipmunk/Makefile
    cd chipmunk && make PREFIX=$out -f Makefile
  '';

  doCheck = false;

  installPhase = ''
    mkdir -p $out/bin
    cp udpxy $out/bin
  '';
}
