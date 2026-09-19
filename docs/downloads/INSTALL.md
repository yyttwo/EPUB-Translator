# 安装 EPUB Translator

![EPUB翻译下载安装三步引导](../assets/screenshots/download-guide.svg)

## 选择适合你的版本

| 平台 | 下载 |
| --- | --- |
| Apple 芯片 Mac | [EPUB-Translator-v1.0.1.dmg](https://github.com/yyttwo/EPUB-Translator/releases/download/v1.0.1/EPUB-Translator-v1.0.1.dmg) |
| Windows 11 x64（Intel/AMD） | [EPUB-Translator-Windows-x64-v0.1.0.zip](https://github.com/yyttwo/EPUB-Translator/releases/download/windows-v0.1.0/EPUB-Translator-Windows-x64-v0.1.0.zip) |

## 使用 DMG 安装（推荐）

1. 从 [GitHub Releases](../../releases/tag/v1.0.1) 下载 `EPUB-Translator-v1.0.1.dmg`。
2. 双击打开 DMG。
3. 将“EPUB翻译.app”拖入 Finder 左侧的“应用程序”文件夹。
4. 从“应用程序”中打开“EPUB翻译”。

## 第一次启动被 macOS 阻止

v1.0.1 尚未经过 Apple Developer ID 签名或 Apple 公证，因此 macOS 可能阻止第一次启动。

1. 尝试打开“EPUB翻译”。
2. 打开“系统设置”。
3. 进入“隐私与安全性”。
4. 向下找到关于“EPUB翻译”被阻止的提示。
5. 点击“仍要打开”，再按系统提示确认。

不需要关闭 Gatekeeper，不需要使用 `sudo`，也不建议运行来源不明的终端命令。

## 使用 ZIP 安装

如果更习惯 ZIP，可下载 `EPUB-Translator-v1.0.1.zip`，解压后将“EPUB翻译.app”拖入“应用程序”文件夹。DMG 仍是推荐方式。

## Windows x64 v0.1.0

1. 下载 Windows x64 ZIP。
2. 使用 [SHA256SUMS.txt](https://github.com/yyttwo/EPUB-Translator/releases/download/windows-v0.1.0/SHA256SUMS.txt) 校验文件。
3. 使用 Windows 资源管理器或 7-Zip 完整解压。
4. 进入解压目录并打开 `EPUBTranslator.App.exe`。

不要直接在 ZIP 压缩包内部运行程序。Windows 版当前未进行代码签名；不要为了运行它关闭 Defender、SmartScreen 或其他系统安全保护。

## 第一次使用

1. 打开 App 左侧的“API 管理”。
2. 选择 Qwen 或 DeepSeek。
3. 输入从对应服务商获得的 API Key。
4. 点击“验证”。只有验证通过后，该 API 才可用于翻译。
5. 返回“翻译”，选择 DRM-free 英文 EPUB。
6. 选择翻译模式并开始翻译。

### macOS 当前界面

![macOS 翻译页](../assets/screenshots/macos-v1.0.1/translate.png)

![macOS API 管理页](../assets/screenshots/macos-v1.0.1/api-manager.png)

![macOS 关于与帮助页](../assets/screenshots/macos-v1.0.1/about-help.png)

### Windows x64 当前界面

![Windows 翻译页](../assets/screenshots/windows-preview-v0.1.0/translate.png)

![Windows API 管理页](../assets/screenshots/windows-preview-v0.1.0/api-manager.png)

![Windows 关于与帮助页](../assets/screenshots/windows-preview-v0.1.0/about-help.png)

EPUB翻译不会持久保存您的 API Key。
API Key 仅在当前 App 运行期间使用，退出 App 后即清除。
下次启动时需要重新输入。

App 不读取或写入 macOS 钥匙串。恢复未完成的翻译任务时，也需要重新输入并验证 API Key。
