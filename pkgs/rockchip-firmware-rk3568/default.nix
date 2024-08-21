{ pkgs, fetchFromGitHub, lib, ... }:

pkgs.stdenv.mkDerivation rec {
  pname = "rockchip-firmware-rk3568";
  version = "2022.08";

  src = fetchFromGitHub ({
    owner = "rockchip-linux";
    repo = "rkbin";
    rev = "b0c100f1a260d807df450019774993c761beb79d";
    sha256 = "sha256-V7RcQj3BgB2q6Lgw5RfcPlOTZF8dbC9beZBUsTvaky0=";
  });

  filesToInstall = [
    "bin/rk35/rk3568_bl31_v1.34.elf"
    "bin/rk35/rk3568_ddr_1560MHz_v1.13.bin"
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
