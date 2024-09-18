{ pkgs, buildUBoot, fetchurl, ... }:
let
# TODO: why boot.binfmt.emulatedSystems not working?
  plat = pkgs.pkgsCross.aarch64-multiplatform;
  version = "2024.07";
in
plat.buildUBoot {
  version = "${version}";
  src = fetchurl {
    url = "https://github.com/u-boot/u-boot/archive/refs/tags/v${version}.tar.gz";
    hash = "sha256-t/YTesyJ5Kk5B1YA3joEzDqGAvqTYZTCe9mhQAW8Yf0=";
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

  BL31 = "${pkgs.rockchip-firmware-rk3568}/rk3568_bl31_v1.44.elf";
  ROCKCHIP_TPL = "${pkgs.rockchip-firmware-rk3568}/rk3568_ddr_1560MHz_v1.21.bin";
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
