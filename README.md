# EPUB翻译

EPUB翻译是一款免费的原生 macOS EPUB 英译中工具。它使用用户自行提供的 Qwen（通义千问）或 DeepSeek API Key，在保留章节结构、封面、书内图片和主要排版的前提下生成简体中文 EPUB。

当前源码快照对应：`1.0.1 (4)`。

## 主要功能

- 导入并分析 EPUB，显示正文文件数、翻译单元数、进度百分比和预计用时
- 支持 Qwen 与 DeepSeek，并在开始翻译前验证 API Key
- 提供直译版、通畅版、意译版和书面评论体四种翻译风格
- 支持失败重试、跳过当前内容和断点进度保留
- 重新打包时保留原书封面、图片、SVG、章节顺序与导航结构
- 完成后提供译本保存与定位入口

## API Key 与隐私

EPUB翻译不会持久保存您的 API Key。

API Key 仅在当前 App 运行期间使用，退出 App 后即清除。

下次启动时需要重新输入。

App 不访问 macOS 钥匙串。电子书内容只会在翻译所需的范围内发送给用户选择的云端 AI 服务。详情见 [PRIVACY.md](PRIVACY.md)。

## 下载成品 App

不想自行编译的用户可以前往独立的[二进制发布仓库](https://github.com/yyttwo/EPUB-Translator-Releases/releases/latest)下载正式版本。二进制发布与本源码仓库相互独立。

## 从源码构建

需要 macOS 与 Xcode。仓库不使用第三方 Swift 包，也不依赖本机其他源码目录。

```bash
./scripts/build.sh
./scripts/test.sh
./scripts/test-ui.sh
```

更多信息见 [DEVELOPMENT.md](DEVELOPMENT.md) 与 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

Copyright 2026 yyttwo。

本项目采用 [Apache License 2.0](LICENSE) 开源。归属信息见 [NOTICE](NOTICE)，第三方与平台相关说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 安全

请勿在 Issue、日志或截图中提交 API Key、私人 EPUB、个人文件路径或其他敏感信息。安全问题请按 [SECURITY.md](SECURITY.md) 的方式报告。
