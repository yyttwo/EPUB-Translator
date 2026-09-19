# EPUB翻译 / EPUB Translator

EPUB翻译是一款免费的跨平台 EPUB 英译中工具，支持 macOS 与 Windows。它采用 BYOK（Bring Your Own Key）模式，使用用户自行提供的 Qwen（通义千问）或 DeepSeek API Key，在保留章节结构、封面、图片、链接和主要排版的前提下生成简体中文 EPUB。

本仓库现已统一保存 macOS、Windows 源码、使用说明、界面截图与版本下载。旧的下载和 Windows Preview 仓库仅用于历史兼容。

## 立即下载

| 平台 | 下载 | 状态 |
| --- | --- | --- |
| Apple 芯片 Mac | [macOS v1.0.1 DMG](https://github.com/yyttwo/EPUB-Translator/releases/tag/v1.0.1) | 正式版 |
| Windows 11 x64（Intel/AMD） | [Windows x64 Preview](https://github.com/yyttwo/EPUB-Translator/releases/tag/windows-v0.1.0-preview.1) | 预览版 |

普通用户不需要下载源码。macOS 用户打开 DMG 后将 App 拖入“应用程序”；Windows 用户应完整解压 ZIP，再运行 `EPUBTranslator.App.exe`。详细步骤见[安装指南](docs/downloads/INSTALL.md)。

![EPUB翻译下载安装三步引导](docs/assets/screenshots/download-guide.svg)

> Windows 版目前是未签名的 x64 Preview，不是正式稳定版。使用前请核对 Release 中公布的 SHA-256，不要关闭 Defender 或 SmartScreen。

## 界面预览

### macOS v1.0.1

| 翻译 | API 管理 | 关于与帮助 |
| --- | --- | --- |
| ![macOS 翻译页](docs/assets/screenshots/macos-v1.0.1/translate.png) | ![macOS API 管理页](docs/assets/screenshots/macos-v1.0.1/api-manager.png) | ![macOS 关于与帮助页](docs/assets/screenshots/macos-v1.0.1/about-help.png) |

### Windows x64 Preview v0.1.0

| 翻译 | API 管理 | 关于与帮助 |
| --- | --- | --- |
| ![Windows 翻译页](docs/assets/screenshots/windows-preview-v0.1.0/translate.png) | ![Windows API 管理页](docs/assets/screenshots/windows-preview-v0.1.0/api-manager.png) | ![Windows 关于与帮助页](docs/assets/screenshots/windows-preview-v0.1.0/about-help.png) |

## 功能

- DRM-free EPUB → 简体中文 EPUB
- 支持 Qwen 与 DeepSeek
- 直译、通畅、意译和书面评论体四种翻译风格
- 保留章节、封面、图片、链接和基本排版
- 支持失败重试和断点进度
- 用户自行提供 API Key；项目不销售 Token，也没有中转服务器

## 核心代码入口

### macOS 核心代码

- [`app/macOS/Sources/EPUBTranslatorApp`](app/macOS/Sources/EPUBTranslatorApp)：Swift/SwiftUI 界面、EPUB 解析与重建、翻译流程、服务商连接和进度保存。
- [`app/macOS/Sources/EPUBTranslatorHelper`](app/macOS/Sources/EPUBTranslatorHelper)：随 App 运行的辅助进程。
- [`app/macOS/Tests`](app/macOS/Tests)：macOS 单元测试与界面测试。

### Windows 核心代码

- [`app/windows/src/EPUBTranslator.Core`](app/windows/src/EPUBTranslator.Core)：翻译核心、服务商连接、任务状态、公共模型和错误处理。
- [`app/windows/src/EPUBTranslator.Platform.Windows`](app/windows/src/EPUBTranslator.Platform.Windows)：Windows Credential Manager、文件选择、AppData 和系统功能。
- [`app/windows/src/EPUBTranslator.App`](app/windows/src/EPUBTranslator.App)：WinUI 3 界面与程序入口。
- [`app/windows/tests`](app/windows/tests)：Windows 核心与平台测试。

### 其他公开内容

- [`fixtures`](fixtures)：项目自制、可公开的测试 EPUB。
- [`docs`](docs)：安装说明、版本记录和界面截图。
- [`scripts`](scripts)：构建、测试与安全扫描脚本。

### macOS 构建

需要 macOS 与 Xcode：

```bash
./scripts/build.sh
./scripts/test.sh
./scripts/test-ui.sh
```

### Windows 构建

需要 Windows 11、.NET 10 SDK 和相应 Windows 构建工具。进入 `app/windows` 后运行：

```powershell
dotnet restore EPUBTranslator.Windows.sln -p:Platform=x64
dotnet build EPUBTranslator.Windows.sln --no-restore -c Release -p:Platform=x64
dotnet test tests/EPUBTranslator.Core.Tests/EPUBTranslator.Core.Tests.csproj --no-restore -c Release -p:Platform=x64
dotnet test tests/EPUBTranslator.Windows.Tests/EPUBTranslator.Windows.Tests.csproj --no-restore -c Release -p:Platform=x64 -p:RuntimeIdentifier=win-x64
```

## API Key 与隐私

EPUB 文件结构在本机处理。翻译所需的文本片段及少量相邻上下文会直接发送给用户选择的 AI 服务商，不经过 EPUB Translator 项目服务器。

不要在 Issue、日志或截图中提交 API Key、私人 EPUB、个人路径或其他敏感信息。详情见 [PRIVACY.md](PRIVACY.md) 与 [SECURITY.md](SECURITY.md)。

## 支持与更新

- [安装指南](docs/downloads/INSTALL.md)
- [更新记录](docs/downloads/CHANGELOG.md)
- [获得支持](docs/downloads/SUPPORT.md)
- [参与开发](CONTRIBUTING.md)

## 许可证

Copyright 2026 yyttwo。

本项目采用 [Apache License 2.0](LICENSE) 开源。第三方组件说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [Windows 第三方组件说明](app/windows/THIRD_PARTY_NOTICES.md)。
