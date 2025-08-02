{
  pkgs,
  fetchFromGitHub,
  lib,
  ...
}:

pkgs.stdenv.mkDerivation rec {
  pname = "rockchip-firmware-rk3568";
  version = "2024.02";

  src = fetchFromGitHub ({
    owner = "rockchip-linux";
    repo = "rkbin";
    rev = "a2a0b89b6c8c612dca5ed9ed8a68db8a07f68bc0";
    sha256 = "sha256-U/jeUsV7bhqMw3BljmO6SI07NCDAd/+sEp3dZnyXeeA=";
  });

  filesToInstall = [
    "bin/rk35/rk3568_bl31_v1.44.elf"
    "bin/rk35/rk3568_ddr_1560MHz_v1.21.bin"
  ];

  installDir = "$out";

  buildPhase = "find .";

  installPhase = ''
    runHook preInstall

    mkdir -p ${installDir}
    cp ${lib.concatStringsSep " " filesToInstall} ${installDir}

    runHook postInstall
  '';

  dontStrip = true;

  meta = with lib; {
    homepage = "https://github.com/rockchip-linux/rkbin";
    description = "RockChip RK3568 Firmware";
    license = [ licenses.unfreeRedistributable ];
  };
}
