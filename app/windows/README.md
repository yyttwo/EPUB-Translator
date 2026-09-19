# EPUB Translator for Windows

This directory contains the native Windows implementation of EPUB Translator.

## Requirements

- Windows 11
- .NET 10 SDK
- Visual Studio Build Tools with Windows application development support

## Build and test

Run these commands from this directory on Windows:

```powershell
dotnet restore EPUBTranslator.Windows.sln -p:Platform=x64
dotnet build EPUBTranslator.Windows.sln --no-restore -c Release -p:Platform=x64
dotnet test tests/EPUBTranslator.Core.Tests/EPUBTranslator.Core.Tests.csproj --no-restore -c Release -p:Platform=x64
dotnet test tests/EPUBTranslator.Windows.Tests/EPUBTranslator.Windows.Tests.csproj --no-restore -c Release -p:Platform=x64 -p:RuntimeIdentifier=win-x64
```

The Windows application is currently a preview. It is distributed as an unpackaged, self-contained ZIP and uses the user's own provider API key.
