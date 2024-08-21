# format sdcard

```
# fdisk -l /dev/mmcblk0
Disk /dev/mmcblk0: 58.61 GiB, 62929764352 bytes, 122909696 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: gpt
Disk identifier: D918101B-CB45-42F2-93E3-426D6927D250

Device         Start       End   Sectors  Size Type
/dev/mmcblk0p1 32768 122909662 122876895 58.6G EFI System
```

## install u-boot
```
nix build .#packages.aarch64-linux.uboot-nanopi-r5s
```

```
cd result
dd if=idbloader.img of=/dev/mmcblk0 seek=64
dd if=u-boot.itb of=/dev/mmcblk0 seek=16384
```

<https://u-boot.readthedocs.io/en/latest/board/rockchip/rockchip.html#flashing>
<https://opensource.rock-chips.com/wiki_Boot_option>

## install root-fs
```
nix build .#nixosConfigurations.r5c.config.system.build.rootfsImage
```

```
dd if=result of=/dev/mmcblk0p1

resize2fs /dev/mmcblk0p1
```