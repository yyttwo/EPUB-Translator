# 开发说明

## 项目结构

- `app/macOS/`：Swift、SwiftUI 原生 macOS App、辅助进程与测试。
- `app/windows/`：.NET 10、WinUI 3 原生 Windows App 与测试。
- `fixtures/`：完全自创的最小 EPUB 测试资料。
- `scripts/`：macOS 构建、测试、Fixture 生成和安全扫描入口。
- `docs/`：安装说明、发布记录、截图和开源审计资料。

## macOS 开发环境

- macOS 13 或更高版本
- Xcode（包含 macOS SDK 与 `xcodebuild`）
- `rg`，用于本地隐私与密钥扫描

项目使用 Apple 系统框架，不包含 Swift Package Manager、CocoaPods 或其他第三方 Swift 源码依赖。

```bash
./scripts/build.sh
./scripts/test.sh
./scripts/test-ui.sh
```

可通过 `DERIVED_DATA_PATH` 指定构建缓存位置。界面测试使用临时目录，不应引用用户的真实 EPUB。

## Windows 开发环境

- Windows 11
- .NET 10 SDK
- 包含 Windows 应用开发组件的 Visual Studio Build Tools

完整命令见 [`app/windows/README.md`](app/windows/README.md)。Windows CI 会在 GitHub 的真实 Windows x64 runner 上执行构建和测试。

## 外部 EPUB 验收

macOS 单元测试可选读取 `EPUB_TRANSLATOR_ACCEPTANCE_EPUB` 环境变量。只应在本机临时使用合法且已获授权的文件；测试不会把路径或文件加入仓库。

## 云端服务

运行 App 时由用户选择 Qwen 或 DeepSeek，并提供对应 API Key。电子书内容只在完成翻译所需的范围内发送给用户选择的服务商，不经过 EPUB Translator 项目服务器。

## 发布边界

源码树不保存 DMG、ZIP、签名 App 或构建缓存。可下载版本通过本仓库的 GitHub Releases 发布。
