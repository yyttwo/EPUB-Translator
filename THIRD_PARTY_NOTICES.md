# 第三方组件说明

## 随仓库提供的源码与素材

macOS 源码不包含第三方 Swift 包、第三方源代码、字体或参考截图。App 图标与代码生成的界面装饰属于本项目素材。`fixtures/stage-1-self-authored.epub` 及其可读源文件为本项目自创测试资料。

Windows 使用的 NuGet 组件与许可证见 [`app/windows/THIRD_PARTY_NOTICES.md`](app/windows/THIRD_PARTY_NOTICES.md)。这些依赖由构建环境恢复，二进制文件不提交到源码树。

## 平台框架

macOS 版本调用 Foundation、SwiftUI、AppKit、UniformTypeIdentifiers、CryptoKit、Compression 与 XCTest 等 Apple 平台框架。Windows 版本使用 .NET、WinUI 3 和 Windows App SDK。平台框架由对应 SDK 提供，其使用受平台条款约束。

## 网络服务

项目通过公开网络接口连接 Qwen（通义千问）与 DeepSeek。仓库不包含服务商 SDK、模型或密钥。服务名称与商标归各自权利人所有；用户使用服务时需遵守相应条款。

## EPUB 标准

项目读取和生成 EPUB 文件格式。仓库未复制或再分发标准组织的实现代码或文档正文。

## 许可证关系

本项目自身的代码与素材依据根目录 `LICENSE` 中的 Apache License 2.0 提供。以上平台、服务和格式说明仅用于准确描述外部接口与运行环境，不主张相关商标、服务、SDK、模型或标准属于本项目。
