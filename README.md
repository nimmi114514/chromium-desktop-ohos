# Chromium 2in1 HAP

本地工作区的移植目标为 **Google Chromium 158.0.8116.0 / OHOS arm64 / API 26**，
源码固定在 Google main 提交 `566635fe3ce2912169a6ca76a00a7ee1d8e400e9`。
使用本机 DevEco Studio 26 内置的 API 26 SDK，原生移植工程位于
[`../chromium158-ohos/`](../chromium158-ohos/README.md)。
完整浏览器与 HAP 是否已经生成，以该工程的
[STATUS.md](../chromium158-ohos/STATUS.md) 和实际构建产物为准。

DevEco Studio 打开本目录；Chromium C++ 改动在相邻的 `chromium158-ohos`
工作区进行，其中 `src` 指向 WSL 中的源码。两者通过运行时准备脚本连接：

| 文件位置 | 用途 |
| --- | --- |
| `../chromium158-ohos/src/out/OHOS/` | Chromium 原生编译输出 |
| `chromium/libs/arm64-v8a/` | 打包使用的 `libchrome_main_web.so` 与 `libadapter.so` |
| `web_engine/src/main/resources/resfile/` | 打包使用的 ICU、PAK 和 V8 快照 |
| `chromium/build/default/outputs/default/chromium-default-signed.hap` | 安装到设备的签名包 |

每次更新内核后，`build_hap.py --stage hap --build-mode release` 会调用
`scripts/prepare_chromium_runtime.sh` 同步库和资源，再生成新 HAP。
安装该新 HAP 才会更新设备中的内核。应用外壳的 `1.0.0` 版本号与
Chromium 内核的 `158.0.8116.0` 分别记录。

入口模块已启用 `compressNativeLibs: true`。运行时准备脚本保留全部语言
PAK，排除仅供构建分析的 `.pak.info` 文件。

在已配置好的 WSL 工作区中构建 158：

```sh
cd ../chromium158-ohos
python3 scripts/build_native.py --stage chrome --jobs 8 --keep-going 0
python3 scripts/build_hap.py --stage hap --build-mode release
```

以下保留原始 132 工程说明，供追溯上游依赖与工程来源；本地 158 的构建方式
和当前验证范围以上述移植工程为准。

## 当前158实现与本地签名

已补齐密码填充前使用鸿蒙屏幕锁定认证的入口、PIN能力查询和认证结果传递。
取消、失败和未录入凭据均不会被当作认证成功。界面开关与翻译的原生改动位于相邻内核仓库。
窗口隐私状态的释放修正也在内核仓库中；菜单尺寸本轮未调整。

签名证书、私钥、密码和本机路径不提交。仓库中的 `build-profile.json5` 只保留
API 26 工程配置；构建签名 HAP 前，请在 DevEco Studio 的签名配置中选择自己的证书。
当前开发机的签名配置仅保留在本地，不属于仓库交付内容。

## 原始 132 工程说明

将 OpenHarmony Chromium `pc_chromium_132` 分支打包为 **HarmonyOS 6.1.1（API 24）** Stage 模型的 HAP，适配 **2in1 / 平板** 设备。

## 特性

- Chromium 132 内核（`pc_chromium_132` 分支）
- 桌面版 User-Agent，桌面模式网页体验
- 支持 Google 账号登录与同步（需要自备 OAuth client id / 代理环境）
- 高刷新率（支持 90Hz / 120Hz / 144Hz 平板，跟随系统显示刷新率）
- HDR 播放：10bit EGL 输出、PQ 亮度映射、HDR 色彩空间切换
- 沉浸式状态栏，可隐藏系统状态栏
- 视频硬解（OHOS 视频解码器，失败时回退软件解码）

## 目录结构

```text
AppScope/                 # 应用级配置
chromium/                 # HAP 主模块（ArkTS 壳 + 原生运行时）
web_engine/               # Web 引擎封装模块
scripts/                  # Chromium runtime 准备脚本
```

## 构建 Chromium

Chromium 本体需要在独立的 manifest 工作区中构建（不要在 HAP 目录下执行）：

```sh
mkdir -p /path/to/chromium_workspace
cd /path/to/chromium_workspace
repo init -u https://gitcode.com/openharmony-tpc/manifest.git \
  -b pc_chromium_132 -m chromium.xml --no-repo-verify
repo sync -c
repo forall -c 'git lfs pull'
./build.sh -t chrome_main_web
```

构建产物位于 `src/out/musl_64/`。macOS 无法提供上游要求的完整 Linux 工具链，请按上游文档在 Linux 构建环境执行。

## 准备 HAP 运行时

```sh
./scripts/prepare_chromium_runtime.sh /path/to/chromium_workspace
```

参数可以是 manifest 工作区根目录（包含 `src/`）或 Chromium 源码根目录。脚本会校验并拷贝原生库与运行资源，不会提交生成物。

## 在 DevEco Studio 中构建

- DevEco Studio 6.1.1 Release（HarmonyOS SDK 6.1.1 / API 24）
- 打开本目录作为 HarmonyOS 工程，配置自己的签名（仓库不包含签名配置）
- 构建默认 HAP：`build/default/outputs/default/`

> 注意：`AppScope/app.json5` 中的 bundle name 为示例值 `com.example.ohos.chromium2in1`，发布前请替换为自有 bundle name 并使用生产签名。

## 安装与启动

```sh
hdc install chromium-default-signed.hap
hdc shell aa start -a EntryAbility -b com.example.ohos.chromium2in1
```

## 说明

- 本仓库只包含工程源码与构建脚本，不包含 Chromium 二进制、签名文件、维护记录等本地敏感信息。
- Release 发布为 unsigned HAP，请自行签名后安装。
- 原生库为 arm64 架构，适配 HarmonyOS 2in1 设备。
