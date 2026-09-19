# 源码目录

- `EPUBTranslator.Core`：平台无关的产品模型、稳定标识、错误类型、翻译服务与接口，不引用 WinUI 或 Windows API。
- `EPUBTranslator.Platform.Windows`：Credential Manager、Windows App SDK 文件选择器、AppData、安全文件复制和默认浏览器适配器。
- `EPUBTranslator.App`：WinUI 3 应用入口，以及“翻译”“API 管理”“关于与帮助”三个页面。
