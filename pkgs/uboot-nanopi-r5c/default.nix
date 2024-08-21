{ pkgs, buildUBoot, fetchurl, ... }:
let
  version = "2024.04";
in
buildUBoot {
  version = "2024.04";
  src = fetchurl {
    url = "https://github.com/u-boot/u-boot/archive/refs/tags/v${version}.tar.gz";
    hash = "sha256-1rV85XSgoFBKW2WWZEzqy393vek1N3m88v3gfEuaK5I=";
  };
  defconfig = "nanopi-r5c-rk3568_defconfig";
  extraMeta.platforms = [ "aarch64-linux" ];

  nativeBuildInputs = with pkgs; [
    ncurses # tools/kwboot
    bc
    bison
    dtc
    flex
    openssl
    (buildPackages.python3.withPackages (p: [
      p.libfdt
      p.setuptools # for pkg_resources
      p.pyelftools
    ]))
    swig
    which # for scripts/dtc-version.sh
  ];

  BL31 = "${pkgs.rockchip-firmware-rk3568}/rk3568_bl31_v1.34.elf";
  ROCKCHIP_TPL = "${pkgs.rockchip-firmware-rk3568}/rk3568_ddr_1560MHz_v1.13.bin";
  enableParallelBuilding = true;
  /*
    patches = [
    ./015-uboot-add-NanoPi-R5S-board.patch
    ./018-driver-Makefile-support-adc-in-SPL.patch
    ./019-rockchip-handle-bootrom-mode-in-spl.patch
    ./120-clk-scmi-Add-Kconfig-option-for-SPL.patch
    ];
  */
  filesToInstall = [ "spl/u-boot-spl.bin" "u-boot.itb" "idbloader.img" ];
}
