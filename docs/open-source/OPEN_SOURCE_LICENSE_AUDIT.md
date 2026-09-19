# 开源许可证审计

审计日期：2026-09-09
候选版本：1.0.1 (4)

## 项目许可证

仓库在 `LICENSE` 中包含完整、未经修改的 Apache License 2.0 原文。项目版权与归属记录在 `NOTICE` 中，App 元数据使用相同的公开版权主体。仓库不需要也不包含私人法定姓名或私人邮箱地址。

`LICENSE_SELECTED=Apache-2.0`
`LICENSE_COMPLIANCE=PASS`

## 依赖审查

- macOS 源码未发现 Swift Package Manager、CocoaPods、Carthage、本地软件包或私有仓库依赖。
- 运行时代码使用 macOS/Xcode 提供的 Apple 平台框架。
- Qwen 和 DeepSeek 通过本项目实现的网络协议访问，不捆绑其 SDK、模型、凭据或服务端代码。
- Windows 依赖及其许可证单独记录在 `app/windows/THIRD_PARTY_NOTICES.md`。

## 素材审查

- App 图标：项目自有素材。
- 界面装饰：由项目界面代码生成。
- EPUB Fixture：项目自行创作，源文件与来源说明存放在 `fixtures/`。
- 第三方字体和图片：未捆绑。

## 结论

未发现第三方再分发冲突。项目许可证、版权说明、贡献条款和 App 元数据与 Apache License 2.0 一致。
