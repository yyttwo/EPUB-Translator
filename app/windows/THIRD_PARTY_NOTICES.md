# Windows 第三方组件说明

Windows 源码引用以下构建、界面和测试包。仓库不提交这些包的二进制文件，由 NuGet 在 Windows 构建环境中恢复。

| 组件 | 固定版本 | 用途 | 许可证 |
| --- | ---: | --- | --- |
| Microsoft.WindowsAppSDK | 2.4.0 | WinUI 3 与 Windows App SDK | Microsoft 软件包许可证 |
| Microsoft.Windows.SDK.BuildTools | 10.0.28000.2705 | Windows SDK 构建工具 | Microsoft 软件包许可证 |
| Microsoft.Windows.SDK.BuildTools.WinApp | 0.6.1 | WinUI `dotnet run` 支持 | MIT |
| Microsoft.NET.Test.Sdk | 18.10.0 | .NET 测试宿主集成 | MIT |
| MSTest.TestAdapter | 4.4.0 | MSTest 测试发现与执行 | MIT |
| MSTest.TestFramework | 4.4.0 | 单元测试框架 | MIT |

应用通过 Windows `advapi32` API 直接调用 Windows Credential Manager，不引入第三方凭据软件包。

Qwen 和 DeepSeek 是外部网络服务。仓库不包含服务商 SDK、模型、凭据或服务端代码。

品牌图标来自本项目现有的 Apache-2.0 公开源码。测试 EPUB 由本项目专门创作，详见 `fixtures/FIXTURE_PROVENANCE.md`。

发布二进制文件前，应再次审计恢复结果与传递依赖，并根据实际锁定的依赖图生成随包说明。
