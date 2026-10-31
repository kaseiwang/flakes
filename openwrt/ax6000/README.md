# AX6000 固件构建

为 Xiaomi Redmi Router AX6000 的 OpenWrt U-Boot layout 构建 OpenWrt 25.12.6
sysupgrade 镜像。构建不会连接或刷写路由器。

在仓库根目录、x86_64 Linux 主机上执行：

```sh
nix run .#build-openwrt-ax6000 -- --output ./private-artifacts/ax6000
```

输出目录必须尚不存在。构建程序输出 `.itb`、软件包 manifest、`sha256sums`
和 `build-info.json`。首次运行需下载约 551 MiB 的官方 ImageBuilder 及软件包。

## 配置和凭据

- `default.nix` 固定 OpenWrt 版本和设备 profile；上游源码由根目录 `flake.lock` 固定。
- `configuration.nix` 定义 UCI 配置，`packages.nix` 定义附加包和禁用服务。
- `first-boot.nix` 在系统默认初始化之后应用配置和 root 密码哈希。
- `secrets.yaml` 使用 SOPS 和 age 保存 PPPoE、无线密码和 root 密码哈希。
- `build.py` 仅在调用构建命令时解密，渲染配置并执行最终 ImageBuilder 组装。

编辑凭据：

```sh
sops openwrt/ax6000/secrets.yaml
```

使用本机 SOPS age identity，默认位置为 `~/.config/sops/age/keys.txt`，也可通过
`SOPS_AGE_KEY_FILE` 指定仓库外的密钥文件。现有加密文件使用与 workstation
凭据相同的 age recipient。不要将解密密钥或解密后的配置加入仓库。

Nix store 中只保存构建工具、固定哈希的软件包、配置模板和加密凭据。
最终组装在输出目录旁的临时私有目录执行，成功或失败时清理；最终固件位于
store 外，文件权限为 0600，目录权限为 0700。固件内含运行所需的密码，
不能公开分发。不要用 `nix build --impure` 读取解密后的配置。

## 网络和首次启动

LAN 使用 DHCP，`br-lan` MAC 固定为 `4c:c6:4c:bd:41:bd`，对应 nas0 中的
`10.10.5.10` 保留租约。LAN 桥接 lan2、lan3、lan4；WAN 保留备份中的 PPPoE
和 MAC 配置。双频无线、root 密码及管理服务配置来自 2026-10-31 的备份，
后续构建不依赖该备份文件。

镜像不包含 sing-box。dnsmasq、odhcpd 和 smartdns 禁用；设备通过 nas0 获取
LAN 地址，不对 LAN 提供 DHCP/DNS 服务。SSH 主机密钥和 HTTPS 证书在首次启动
时生成，因此 SSH 指纹会改变。运行期间的手工配置不会同步回 Nix。

固件用于不保留旧配置的 sysupgrade；保留旧配置会覆盖或干扰镜像中的声明配置。
实际刷写前应核对设备为 `xiaomi,redmi-router-ax6000-ubootmod`，并在设备上对
所选镜像执行 `sysupgrade -T`。本构建命令不执行这一步，也不执行刷写。

## 验证和更新

构建会检查 UCI 语法、首次启动脚本语法、包清单及镜像文件系统中的配置。
这些检查不能替代设备上的兼容性检查和启动验证。

升级版本时，同时检查上游缓存中存在该版本，更新 `default.nix` 和对应的
`openwrt-imagebuilder` lock。固定哈希可检测下载内容变化，但上游删除旧软件包
后仍需要已有 Nix 缓存才能重建，因此应保留构建工具及其依赖的缓存。
