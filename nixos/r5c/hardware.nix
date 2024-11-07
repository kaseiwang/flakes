{ config, lib, pkgs, inputs, modulesPath, ... }:
let
  crossPkgs = import pkgs.path {
    localSystem.system = "x86_64-linux";
    crossSystem = {
      system = "aarch64-linux";
      config = "aarch64-unknown-linux-gnu";
    };
  };
in
{
  hardware = {
    enableRedistributableFirmware = lib.mkDefault true;
    deviceTree = {
      name = "rockchip/rk3568-nanopi-r5c.dtb";
    };
  };

  powerManagement.cpuFreqGovernor = "schedutil";

  boot = {
    loader = {
      timeout = 1;
      grub.enable = false;
      generic-extlinux-compatible = {
        enable = true;
      };
    };
    kernelPackages = crossPkgs.linuxPackages_latest;
    # https://github.com/NixOS/nixos-hardware/blob/master/friendlyarm/nanopi-r5s/default.nix
    kernelPatches = [
      {
        name = "rockchip-config.patch";
        patch = null;
        extraConfig = ''
          PCIE_ROCKCHIP_EP y
          PCIE_ROCKCHIP_DW_HOST y
          ROCKCHIP_VOP2 y
        '';
      }
      {
        name = "status-leds.patch";
        patch = null;
        extraConfig = ''
          LED_TRIGGER_PHY y
          USB_LED_TRIG y
          LEDS_BRIGHTNESS_HW_CHANGED y
          LEDS_TRIGGER_MTD y
        '';
      }
    ];
    initrd = {
      availableKernelModules = [
        ## Rockchip
        ## Storage
        "sdhci_of_dwcmshc"
        "dw_mmc_rockchip"

        "analogix_dp"
        "io-domain"
        "rockchip_saradc"
        "rockchip_thermal"
        "rockchipdrm"
        "rockchip-rga"
        "pcie_rockchip_host"
        "phy-rockchip-pcie"
        "phy_rockchip_snps_pcie3"
        "phy_rockchip_naneng_combphy"
        "phy_rockchip_inno_usb2"
        "dwmac_rk"
        "dw_wdt"
        "dw_hdmi"
        "dw_hdmi_cec"
        "dw_hdmi_i2s_audio"
        "dw_mipi_dsi"
      ];
      kernelModules = [
        "snd_soc_rockchip_i2s_tdm"
        "rockchipdrm"
        "rockchip_thermal"
        "rockchip_saradc"
        "phy_rockchip_naneng_combphy"
        "phy_rockchip_snps_pcie3"
        "phy_rockchip_inno_usb2"
        "dw_mmc_rockchip"
        "r8169"
      ];
    };
    # Let's blacklist the Rockchips RTC module so that the
    # battery-powered HYM8563 (rtc_hym8563 kernel module) will be used
    # by default
    # blacklistedKernelModules = [ "rtc_rk808" ];
    kernelParams = [
      "console=ttyS2,1500000"
      "earlycon=uart8250,mmio32,0xfe660000"
      "mitigations=off"
    ];
    kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = true;
      "net.ipv6.conf.all.forwarding" = true;
      "net.ipv4.conf.default.forwarding" = true;
      "net.ipv6.conf.default.forwarding" = true;
    };
    tmp.useTmpfs = true;
  };

  swapDevices = [ ];
}
