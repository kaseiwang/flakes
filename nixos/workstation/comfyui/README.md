# Workstation ComfyUI / MiniMax H3

本目录由 `../comfyui.nix` 管理，已接入 workstation 的 flake 配置。
仅适用于此主机的 Linux x86_64、Docker、NVIDIA GPU 和 Btrfs 持久化布局。

## Review 要点

- 启用 NVIDIA Container Toolkit / CDI，容器使用 `nvidia.com/gpu=0`。
  RTX 3080 可与 GNOME 同时使用 GPU；容器并不独占 GPU，也没有显存配额隔离。
- ComfyUI 按需启动，不随开机启动；闲置时切换配置不会启动构建或模型下载。
  更新正在运行的容器配置时，switch 可能触发重启并构建新镜像。
- 只发布 `127.0.0.1:8188`；容器内监听 `0.0.0.0` 是为了 Docker 端口转发。
- 专用 `comfyui` 用户及组，UID/GID 均为 `10001`。`kasei` 加入该组；重新登录后生效。
  容器无需 privileged、X11 socket 或 Docker socket。
- `/var/lib/comfyui` 位于已有 `/var/lib` 持久化挂载中。
  `models` 和 `cache` 首次手动运行服务时创建为嵌套 Btrfs 子卷，不进入现有
  `nixos_persist` 的 Btrfs 快照；`input`、`output`、`user` 随原有备份保存。
  如果已有同名普通目录，准备服务会报错，避免自动移动已有数据。
- Docker 镜像存储沿用已有 `/var/lib/docker`；这里没有修改分区或备份策略。
  模型和缓存不写入根目录或 `/tmp` 的 tmpfs。

## 固定版本与模型

| 组件 | 版本 |
| --- | --- |
| Python | 3.12 slim-bookworm，Dockerfile 中固定 amd64 digest |
| Debian 软件包 | snapshot.debian.org，2026-09-23 快照 |
| ComfyUI | v0.37.0 / `73c9bad4d21e7addbe1d13bc92eee0f1431b017d` |
| ComfyUI-GGUF | leejet fork / `edd981b10e107d3b8f58e16c498f2d08f631bc47` |
| PyTorch / torchvision | 2.13.0+cu130 / 0.28.0+cu130 |
| torchaudio | 2.11.0+cu130，使用支持后续 Torch 版本的稳定 ABI |
| Python 依赖 | `requirements.lock`，全部固定版本及 SHA256 |

基础镜像 digest、源码归档 SHA256、依赖和模型哈希均已固定。
本地镜像标签根据 Dockerfile、锁文件与 `h3-compatibility.patch` 内容生成，
`pull=never`，启动时不更新软件。
标签用于区分构建配置，不是远端 OCI digest，也不承诺构建产物逐字节相同。
镜像内只安装固定的 GGUF 扩展；新增扩展应修改构建配置并重新构建。

`h3-compatibility.patch` 在构建时应用于上述固定源码，解决实测发现的两个兼容问题：

- H3 的原生 GGUF 文本编码器缺少 `general.architecture`。通过特定 tensor 名称与精确形状
  识别该格式，按 Qwen3VL 加载；将未压缩 BF16 字节恢复为 BF16 tensor，并恢复视觉
  Conv3d 的五维形状。其他 GGUF 继续使用原有架构校验，不改写或重新量化模型文件。
- H3 视频 VAE 的 `qk_norm_scale` 在低显存 offload 时可能留在 CPU；在使用前迁移到
  query 的 device/dtype，避免 CPU/CUDA 混用。

构建会先将 GGUF 源码的 CRLF 转为 LF，再以 `--fuzz=0` 应用补丁并检查 Python 语法。
上游更新导致补丁无法应用时构建会失败，需要重新审阅兼容处理。

| 模型集 | 文件 | 大小（十进制 GB） |
| --- | --- | ---: |
| base | FL2VA pruned Q4_K_M GGUF | 11.42 |
| base | H3 专用 Qwen3VL 32B Q4_K_M GGUF | 18.22 |
| base | Video VAE INT8 ConvRot | 2.81 |
| base | Audio VAE FP32 | 0.61 |
| turbo（可选） | FL2V 8-step LoRA BF16 | 1.96 |
| ref2va（可选） | Ref2VA pruned Q4_K_M GGUF | 11.42 |

基础模型共约 **33.06 GB / 30.78 GiB**，加上镜像、构建缓存、输出视频需要更多磁盘空间。
模型来自 `leejet/MiniMax-H3-GGUF` 和 `Comfy-Org/MiniMax-H3`；revision、路径、字节数
和 SHA256 在 `models.json` 中。下载支持断点续传，校验通过才将 `.partial` 改为最终文件名。
已存在的最终文件也会校验；发现损坏会报错，需人工移走对应文件后重试。

Q4_K_M 是混合量化，并非每个张量恰好 4 bit。文件大小也不等于推理显存。
3080 无原生 NVFP4 Tensor Core；此配置选用 GGUF。Q4 文本编码器文件反而比
NVFP4 版本大；选择它是为了遵循 GGUF 偏好，并使用该加载器的量化路径。

## Review 后部署

先确保新增文件进入 Git 索引，否则普通 Git flake 引用看不到这些文件；也可以用
`path:/home/kasei/flakes#workstation` 对未提交工作区求值。

```sh
# Review 通过后再执行；本次实现不执行 switch。
sudo nixos-rebuild switch --flake path:/home/kasei/flakes#workstation

# 两步独立执行，便于观察镜像构建和大文件下载。
sudo systemctl start comfyui-image.service
sudo systemctl start comfyui-models@base.service

# 同时在另一终端查看进度。
journalctl -fu comfyui-image.service
journalctl -fu comfyui-models@base.service

# 启动会自动检查目录、镜像及 NVIDIA CDI；不会自动下载模型。
sudo systemctl start docker-comfyui.service
journalctl -fu docker-comfyui.service

# 浏览器打开 http://127.0.0.1:8188
# 用完停止，释放 CUDA 上下文及显存。
sudo systemctl stop docker-comfyui.service
```

镜像构建和模型下载沿用 `networking.proxy` 的代理配置；运行中的 ComfyUI 不依赖它。
首次构建需要访问 Docker Hub、Debian snapshot、PyPI、PyTorch 和 GitHub。
下载模型时需要访问 Hugging Face 及其文件 CDN。权重不会进入 Nix store。

已有部署更新此修复时无需重新下载权重。Review 后执行 switch，再重启服务以使用新镜像：

```sh
sudo nixos-rebuild switch --flake path:/home/kasei/flakes#workstation
sudo systemctl restart docker-comfyui.service
```

如果服务正在运行，switch 可能已触发重启；启动依赖会构建尚不存在的新标签镜像。

可选模型单独下载，不会自动切换工作流：

```sh
sudo systemctl start comfyui-models@turbo.service
sudo systemctl start comfyui-models@ref2va.service
```

远程访问使用 SSH 转发，无需改监听地址：

```sh
ssh -L 8188:127.0.0.1:8188 workstation
```

## 初始工作流与显存设置

首次启动后打开 `minimax-h3-q4-starter.json`。也可将本目录的 `workflow.json` 拖入界面。
它基于模型作者的 FL2V GGUF 示例，已改为：

- `UnetLoaderGGUF` + `CLIPLoaderGGUF`，文本编码器类型 `minimax`；
- INT8 ConvRot 视频 VAE、FP32 音频 VAE；
- 640×384，124 帧，24 fps（约 5.17 秒），单样本；
- `res_multistep` + `simple`，20 步，BasicGuider。

未连接首尾帧时用于文生视频；可接入图片尝试图生视频。自定义后另存为自己的文件，
因为准备服务会更新所提供的 starter 文件。

启动参数使用 `--disable-dynamic-vram --lowvram --reserve-vram 3 --cache-ram 6`。
GGUF 扩展有自己的 ModelPatcher；此起点采用明确的 CPU offload，**文本编码在 CPU 上执行，
预计较慢**。预留显存与缓存 RAM 参数是 ComfyUI 的调度建议，不是硬限制；`cache-ram 6`
表示为系统保留 RAM 余量，不是将缓存限制在 6GB。没有为容器设置容易触发 OOM 的 RAM 硬上限。

10GiB GPU 装不下这组模型，实际依赖约 45GiB 主机内存和 CPU/GPU 交换。
2026-09-25 已在 RTX 3080 上完成上述参数的带音频生成；增大尺寸、帧数或桌面负载时仍需
观察 `nvidia-smi`、系统内存和日志。必要时降低分辨率或帧数（H3 帧数按 `17n+5`）。
turbo LoRA 的 8 步流程尚未验证。

## 更新和检查

修改版本时同时更新源码 SHA256、requirements 输入/锁文件；无需更新整个 flake.lock。
`requirements.in` 包含所固定源码的依赖集合。使用 uv 0.12.18 生成锁文件的命令：

```sh
uv pip compile nixos/workstation/comfyui/requirements.in \
  --python-version 3.12 --python-platform x86_64-manylinux_2_36 \
  --generate-hashes --emit-index-url --index-strategy unsafe-best-match \
  --no-header --output-file nixos/workstation/comfyui/requirements.lock

nix eval --raw path:/home/kasei/flakes#nixosConfigurations.workstation.config.system.build.toplevel.drvPath
git diff --check
```

`unsafe-best-match` 只用于解析阶段跨 PyPI/PyTorch 查找 CUDA wheels；安装阶段启用
`--require-hashes --only-binary=:all:`。更新锁文件仍需要审阅版本和哈希。

2026-09-25 本次实现已通过：工作站完整 Nix 求值、四个新增 systemd unit 构建
（包含 ShellCheck）、Docker 镜像构建及 `pip check`、无网络/无 GPU 的 CPU 启动检查。
H3、GGUF 和 starter 工作流所需节点均成功注册；PyTorch wheel 包含 `sm_86`。
下载器另用本地小文件验证了断点续传、重复运行和校验失败保护。
部署后已完成系统切换、四个基础模型下载及 SHA256 校验、NVIDIA CDI 接入和完整 GPU 生成。
首次测试暴露的 GGUF 加载和 VAE offload 问题已整理为构建补丁。

固化镜像 `localhost/comfyui-h3:6c98077b12a22245f7e94a91e5916f50` 已通过完整 GPU 验证：
独立容器使用正常入口和上述启动参数，关闭网络、只读挂载模型，无运行时补丁注入。
640×384、124 帧、24 fps、20 步、seed 20260925，完整生成用时 **286.69 秒**，
其中采样约 194 秒。输出 H.264 视频与 32kHz AAC 立体声音轨，时长 5.167 秒；
成片位于 `output/video/h3-pinned-6c98077b_00001_.mp4`。
每约 5 秒采样的整卡显存最高为 6119 MiB（5.98 GiB，含桌面与其他进程，不是瞬时峰值）；
该结果不代表其他参数的耗时或显存上限。

另将测试容器的显存预留临时提高到 4 GiB，复用已保存的 latent 单独验证 VAE 分载路径：
视频 VAE 有 1035 MB 权重 offload 到 CPU，音视频解码及保存仍成功，用时 7.04 秒。
正式 flake 继续使用 3 GiB 预留。两个验证容器均已停止，正式服务需部署新配置后更新。

上游参考：

- [ComfyUI v0.37.0](https://github.com/Comfy-Org/ComfyUI/tree/v0.37.0)
- [leejet GGUF 模型与工作流](https://huggingface.co/leejet/MiniMax-H3-GGUF/tree/d9c4c6312b4728a68a15a35626d84775a6523783)
- [Comfy-Org VAE / LoRA](https://huggingface.co/Comfy-Org/MiniMax-H3/tree/1c41cfca8ebba91d0af792a05c5761fb2c3a7975)
- [TorchAudio 稳定 ABI 兼容说明](https://docs.pytorch.org/audio/main/installation.html)
- [NVIDIA CDI 支持](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html)
