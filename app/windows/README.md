# EPUB Translator Windows 版

此目录包含 EPUB Translator 的 Windows 原生实现。

## 环境要求

- Windows 11
- .NET 10 SDK
- 包含 Windows 应用开发组件的 Visual Studio Build Tools

## 构建与测试

在 Windows 中进入本目录并运行：

```powershell
dotnet restore EPUBTranslator.Windows.sln -p:Platform=x64
dotnet build EPUBTranslator.Windows.sln --no-restore -c Release -p:Platform=x64
dotnet test tests/EPUBTranslator.Core.Tests/EPUBTranslator.Core.Tests.csproj --no-restore -c Release -p:Platform=x64
dotnet test tests/EPUBTranslator.Windows.Tests/EPUBTranslator.Windows.Tests.csproj --no-restore -c Release -p:Platform=x64 -p:RuntimeIdentifier=win-x64
```

Windows 版目前为预览版，以未打包、自包含 ZIP 形式分发，使用用户自行提供的服务商 API Key。
