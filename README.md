# Chromium Desktop for OHOS

面向 **HarmonyOS / OHOS 平板与 2in1 设备**的 Chromium 桌面浏览器 HAP 应用工程，当前接入 **Chromium 158.0.8116.0 / arm64 / API 26**。

**本仓库在 [Nyaacho0v0/chromium-2in1-hap](https://github.com/Nyaacho0v0/chromium-2in1-hap) 的 Chromium 132 HAP 工程基础上继续开发。** 原作者及上游社区提供了应用壳、系统接口桥接和打包基础；本项目在这些工作的基础上接入158内核并进行兼容性适配。感谢原作者与相关贡献者。

原132基线提交：[`cc241f6d431c52144afe58f3d4232ca7c9658c43`](https://github.com/Nyaacho0v0/chromium-2in1-hap/commit/cc241f6d431c52144afe58f3d4232ca7c9658c43)。本仓库保留该基线的 Git 历史及沿用文件中的版权和许可声明。

## 配套内核仓库

| 仓库 | 内容 |
| --- | --- |
| [chromium-ohos](https://github.com/nimmi114514/chromium-ohos) | Chromium 158 内核及依赖适配补丁、构建工具、验证记录 |
| [chromium-desktop-ohos](https://github.com/nimmi114514/chromium-desktop-ohos)（本仓库） | ArkTS 应用壳、系统桥接、应用配置和 HAP 打包工程 |

本仓库需要配套内核编译产生的原生库、ICU、PAK 语言/界面资源及 V8 快照。更新内核后，需要同步资源并重新生成 HAP，设备中的内核才会更新。

## 相对132工程的主要改动

- 接入固定版本 Chromium 158，使用 API 26 构建配置。
- 使用新包名 `com.example.chromium`，可与设备上现有的 `com.example.ohos.chromium` 并存；安装新包不会删除或覆盖旧包及其数据。
- 适配158的库和资源打包方式，按实际构建配置选择 V8 快照，保留全部语言 PAK。
- 压缩打包原生库，排除运行时不需要的 `.pak.info` 构建映射文件。
- 调整上下文路径和应用存储桥接，匹配当前应用身份。
- 补充显示 HDR、亮度与色彩能力桥接，完善亮度观察者的清理。
- 恢复屏幕锁定认证入口及 PIN 能力查询，正确传递系统认证结果；取消、失败和未录入均不会被当作成功。

标签栏、渲染、媒体解码、密码填充策略及窗口隐私状态等 C++ 改动位于配套内核仓库。应用外壳的 `versionName: 1.0.0` 与 Chromium 内核版本分别记录。

## 当前状态与限制

项目仍在适配和回归阶段。已有桌面界面、中文资源、AVC/HEVC硬件解码、HDR本地样本和WebGPU等方向的实现与验证记录，但不表示所有网站、扩展和系统功能均已验收。

最新 native107 候选已完成 release 编译、打包、包内容及签名校验并安装。最新的每次密码填充独立认证、受保护媒体结束后释放窗口隐私状态等修正，通过了主机模拟检查，尚未完成该候选的设备功能回归。

完整验证范围见内核仓库的 [STATUS.md](https://github.com/nimmi114514/chromium-ohos/blob/master/STATUS.md) 和 [native107 交付记录](https://github.com/nimmi114514/chromium-ohos/blob/master/reports/native107-delivery.json)。

- 硬件解码格式取决于设备能力；HDR网站选流与面板绝对亮度、色准尚未完整验收。
- WebGPU呈现暂未实现零拷贝；Graphite、DrDc、TreesInViz、WebNN当前未启用。
- DRM受保护内容端到端播放尚未完成，不作为当前已支持功能。
- 本分支已声明自带 V8 的 JIT 受限权限，需重新申请包含该 ACL 的有效 Profile；旧签名配置不能直接作为 JIT 授权使用，真机 JIT 尚未验证。参见 [JIT 权限申请与调试签名](docs/JIT_ACL.md)。
- Google登录/同步配置沿用原132工程中的社区公开配置；实际可用性受凭证、网络和服务端策略影响。本仓库不提供登录或同步可用性的保证。

## 目录结构

```text
AppScope/                   应用身份、名称、图标与应用级资源
chromium/                   HAP 入口模块
web_engine/                 ArkTS 系统接口与浏览器应用封装
scripts/                    内核运行时准备脚本
build-profile.json5         API 26 构建配置，仓库不含个人签名配置
chromium/libs/arm64-v8a/     同步后的原生库，不提交
web_engine/src/main/resources/resfile/
                            同步后的 ICU、PAK、V8 快照，不提交
```

## 获取工程

当前自动构建脚本默认使用历史本地目录名。公开仓库名可以保持现在的名称，克隆时指定本地目录即可：

```sh
git clone git@github.com:nimmi114514/chromium-ohos.git chromium158-ohos
git clone git@github.com:nimmi114514/chromium-desktop-ohos.git chromium-2in1-hap
```

目录布局为：

```text
workspace/
├── chromium158-ohos/      内核移植仓库
│   └── src/out/OHOS/     原生编译输出
└── chromium-2in1-hap/    本 HAP 工程
```

也可使用 HTTPS 克隆。若修改本地目录名，打包时需通过内核脚本的 `--hap-project` 指定本工程路径。

## 构建与打包

已用环境为 Windows DevEco Studio 26 + API 26 SDK，以及负责原生内核编译的 WSL2。首次构建请先按[内核仓库 README](https://github.com/nimmi114514/chromium-ohos#获取与构建)准备源码、依赖、工具链和补丁。

### 1. 编译内核

在同级内核移植仓库运行：

```sh
cd chromium158-ohos
python3 scripts/build_native.py --stage chrome --jobs 8 --keep-going 0
```

### 2. 配置本地签名

在 DevEco Studio 打开 `chromium-2in1-hap`，为包名 `com.example.chromium` 配置自己的签名。仓库中的 `build-profile.json5` 不包含个人证书、私钥、密码或签名路径。

配置证书时应与当前应用包名一致。若需要更改包名，还需同步应用和桥接配置，以及内核仓库中的打包校验规则。

### 3. 同步资源并生成 release HAP

继续在内核移植仓库运行：

```sh
python3 scripts/build_hap.py --stage install
python3 scripts/build_hap.py --stage hap --build-mode release
```

`--stage install` 仅安装OHPM工程依赖，不会安装应用到设备。`--stage hap` 会同步当前内核库和资源，然后调用Windows Hvigor生成HAP，完成包内容及签名校验。

若通过 DevEco Studio 手动打包，先在 WSL 中同步运行时：

```sh
cd ../chromium-2in1-hap
bash scripts/prepare_chromium_runtime.sh \
  ../chromium158-ohos/src \
  ../chromium158-ohos/src/out/OHOS
```

第二个参数应显式指定158的 `out/OHOS`；脚本不带该参数时保留原132的 `out/musl_64` 默认值。

### 4. 安装

签名包生成在本工程的：

```text
chromium/build/default/outputs/default/chromium-default-signed.hap
```

使用 DevEco Studio SDK 提供的 `hdc` 安装和启动：

```sh
hdc install -r chromium/build/default/outputs/default/chromium-default-signed.hap
hdc shell aa start -a EntryAbility -b com.example.chromium
```

设备连接多个目标时，请用 `hdc -t <设备标识>` 指定目标。

源码仓库不附带原生库、SDK、HAP安装包或个人签名文件。安装包是否发布及对应构建版本，应以实际Release附件与说明为准。

## 来源与致谢

- **[Nyaacho0v0](https://github.com/Nyaacho0v0)**：本项目直接基于其 [chromium-2in1-hap](https://github.com/Nyaacho0v0/chromium-2in1-hap) Chromium 132 工程继续开发。感谢原作者提供的桌面应用工程、系统适配和打包基础。
- **[OpenHarmony-TPC Chromium 移植项目](https://github.com/OpenHarmony-TPC/chromium_src)**：提供 `pc_chromium_132` 等平台适配工作，是158移植的重要实现参考。
- **[Chromium 项目](https://chromium.googlesource.com/chromium/src/)**及第三方依赖的维护者：提供浏览器内核和基础组件。
- 原始文件中署名的 **Haitai FangYuan** 等贡献者，以及持续完善OHOS生态的社区开发者。

本项目的158适配是在上述工作上继续进行的；沿用文件保留原有版权及许可声明，内核和第三方组件的许可信息见相应上游源码。
