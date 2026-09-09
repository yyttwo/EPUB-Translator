# Development

## 环境

- macOS 13 或更高版本
- Xcode（包含 macOS SDK 与 `xcodebuild`；当前候选已在 Xcode 26.6 验证构建）
- `rg`，用于本地隐私与密钥扫描

项目使用 Apple 系统框架，不包含 Swift Package Manager、CocoaPods 或其他第三方源码依赖。

## 目录

- `app/macOS/Sources/EPUBTranslatorApp/`：主 App
- `app/macOS/Sources/EPUBTranslatorHelper/`：随 App 构建的辅助进程
- `app/macOS/Tests/`：单元测试与界面验收测试
- `fixtures/`：完全自创的最小 EPUB 测试资料
- `scripts/`：本地构建、测试、Fixture 生成和安全扫描入口

## 构建与测试

```bash
./scripts/build.sh
./scripts/test.sh
./scripts/test-ui.sh
```

可通过 `DERIVED_DATA_PATH` 指定构建缓存位置。界面测试会使用临时目录，不需要也不应引用用户的真实 EPUB。

## 外部 EPUB 验收

单元测试可选读取 `EPUB_TRANSLATOR_ACCEPTANCE_EPUB` 环境变量。只应在本机临时使用合法且已获授权的文件；测试不会把该路径或文件加入仓库。

## 云端服务

运行 App 时由用户选择 Qwen 或 DeepSeek，并提供对应 API Key。API Key 只存在于当前进程内存，不持久保存，也不访问 macOS 钥匙串。

## 发布边界

本仓库仅面向源码。DMG、ZIP、签名 App 和 checksums 由独立的二进制发布仓库维护，不应提交到这里。
