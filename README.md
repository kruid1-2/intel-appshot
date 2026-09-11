# Intel Appshot

[English](#english)

> 一个非官方、社区维护的 macOS 兼容性项目，用于在 Intel / x86_64 Mac 上恢复 ChatGPT/Codex 桌面端的 Appshot（智能快照）捕获链路。

## 项目用途

Intel Appshot 实现一个本地 `x86_64` Helper，接收已观测的 Appshot Apple Event 请求，捕获当前前台窗口的 Accessibility 文本和 PNG 截图，然后按客户端期望的顺序返回快照更新。

本项目只处理 **Intel Mac 上的 Appshot / 智能快照兼容**，不重新实现官方 Computer Use action。

## 功能

- 原生 `x86_64` `SkyComputerUseService`。
- 读取前台应用的可访问性树。
- 将同一个 AX 窗口严格映射到 `CGWindowID` 和 `SCWindow`。
- 通过 ScreenCaptureKit 生成真实窗口 PNG。
- 返回 `metadata → axText → screenshot → completed` 快照更新。
- 包含本地打包、签名、安装、身份检查、权限诊断和运行状态检查。
- 快照过渡包含前台激活门控、快门反馈、终点遮罩和边缘处理。

## 支持环境

- Intel / `x86_64` Mac。
- macOS 14 或更高版本。
- Swift 6.2 工具链（Xcode 或 Command Line Tools）。
- 安装了支持 Appshot 入口的 ChatGPT/Codex macOS 桌面端。

这个项目依赖已观测的客户端协议和 macOS 行为。客户端更新可能使兼容性失效。

## 构建

先安装 Xcode Command Line Tools：

```bash
xcode-select --install
```

然后克隆并构建 SwiftPM 项目：

```bash
git clone https://github.com/kruid1-2/intel-appshot.git
cd intel-appshot
swift build --disable-sandbox
swift test --disable-sandbox
```

## 本地签名与安装

仓库不包含任何证书或私钥。打包 Helper 前，请在“钥匙串访问”的证书助理中创建唯一的本地代码签名证书，名称必须是：

```text
Codex Computer Use Local Development
```

构建脚本会自动读取该唯一证书的指纹，并将其用于本机稳定签名。如需额外锁定指纹，可设置 `CODEX_COMPUTER_USE_SIGNING_IDENTITY_SHA1`。

```bash
./script/build_and_run.sh --build
./script/build_and_run.sh --install
./script/build_and_run.sh --start
./script/build_and_run.sh --permissions
./script/build_and_run.sh --doctor
```

Helper 安装到：

```text
~/.codex/computer-use/Codex Computer Use.app
```

`dist/` 只是可重建的开发副本，不是安装来源。仓库目前没有可直接下载的经公证 Release。

## 所需权限

macOS 会要求对本地签名的 Helper 授予：

- 辅助功能（Accessibility）。
- 屏幕与系统音频录制（Screen Recording）。

`--permissions` 只读取状态，不会修改或重置 TCC 权限。授权后请完全退出并重新打开桌面客户端和 Helper。

## 原版资源

仓库不包含 ChatGPT/Appshot 原版二进制、应用包、音效、证书或私钥。缺少可选音效资源时，Helper 仍可构建和工作，但不会播放快门音。

## 已知限制

- 仅支持 Appshot 捕获；不支持鼠标点击、键盘输入、滚动或其他 Computer Use action。
- 仅限 ScreenCaptureKit 可见的屏幕内窗口；最小化、离屏、受保护或 DRM 内容可能无法捕获。
- 使用动态解析的私有 AX 窗口 API，macOS 更新后可能变化。
- 协议代码和客户端行为均可能随桌面端更新而变化。
- 本地签名不是 Developer ID 签名，也没有经过 Apple 公证。
- 项目不包含官方 Computer Use action 服务器。

更详细的协议、签名、安装和验证边界见 [HANDOFF.md](HANDOFF.md)。

## 免责声明

本项目与 OpenAI 无关，未获得 OpenAI 认可、赞助或支持。ChatGPT、Codex 及相关商标归其各自权利人所有。本项目依赖未承诺稳定的客户端行为，仅按现状提供；使用者需自行评估安全、隐私、兼容性和合规风险。

## License

[MIT](LICENSE) © 2026 kruid1-2

---

## English

Intel Appshot is an unofficial, community-maintained macOS compatibility project that restores the Appshot capture path used by the ChatGPT/Codex desktop client on Intel (`x86_64`) Macs.

### Purpose and features

The local Helper receives the observed Appshot Apple Event request, captures Accessibility text and a PNG of the same frontmost window, and returns `metadata → axText → screenshot → completed`. It uses strict AX-window-to-`CGWindowID`-to-`SCWindow` matching, ScreenCaptureKit capture, local signing, verified installation, permission diagnostics, and lifecycle checks.

This project is **snapshot-only**. It does not reimplement official Computer Use actions such as clicking, typing, or scrolling.

### Requirements

- Intel / `x86_64` Mac.
- macOS 14 or later.
- Swift 6.2 toolchain through Xcode or Command Line Tools.
- A ChatGPT/Codex macOS desktop client version that still exposes the observed Appshot integration.

### Build

```bash
xcode-select --install
git clone https://github.com/kruid1-2/intel-appshot.git
cd intel-appshot
swift build --disable-sandbox
swift test --disable-sandbox
```

### Local signing and installation

No certificate or private key is distributed. Create one unique local Code Signing certificate in Keychain Access named `Codex Computer Use Local Development`. The workflow detects that certificate's fingerprint; optionally set `CODEX_COMPUTER_USE_SIGNING_IDENTITY_SHA1` to pin it explicitly.

```bash
./script/build_and_run.sh --build
./script/build_and_run.sh --install
./script/build_and_run.sh --start
./script/build_and_run.sh --permissions
./script/build_and_run.sh --doctor
```

The canonical Helper is installed at `~/.codex/computer-use/Codex Computer Use.app`. `dist/` is only a rebuildable development copy. There is currently no notarized downloadable release.

### Permissions

Grant the locally signed Helper Accessibility and Screen Recording permission in macOS System Settings. `--permissions` is read-only and never resets TCC.

### Limitations and disclaimer

- Only on-screen windows exposed by ScreenCaptureKit can be captured; minimized, off-screen, protected, or DRM content may be unavailable.
- A dynamically resolved private AX window API is used and may change in a future macOS release.
- The observed desktop protocol may change without notice.
- Local signing is neither Developer ID distribution nor Apple notarization.
- Official ChatGPT/Appshot binaries, apps, sounds, certificates, and private keys are not included. The Helper remains functional without the optional sound resource.

This project is not affiliated with, endorsed by, sponsored by, or supported by OpenAI. ChatGPT, Codex, and related marks belong to their respective owners. The software is provided as-is; users are responsible for evaluating security, privacy, compatibility, and compliance risks.

For engineering details and validation boundaries, see [HANDOFF.md](HANDOFF.md).

### License

[MIT](LICENSE) © 2026 kruid1-2
