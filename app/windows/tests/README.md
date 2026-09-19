# Windows 测试

`EPUBTranslator.Core.Tests` 覆盖翻译模式、服务商标识、凭据抽象、扩展名与路径策略、输出文件隔离、错误处理和支持链接。

`EPUBTranslator.Windows.Tests` 覆盖 AppData 目录策略、文件复制行为，以及可选的 Credential Manager 集成测试。Windows 专属测试必须在真实 Windows 环境运行。

凭据集成测试只使用 `FAKE_QWEN_SECRET` 和 `FAKE_DEEPSEEK_SECRET`。除非设置 `EPUB_TRANSLATOR_RUN_CREDENTIAL_TESTS=1`，该测试不会运行；测试结束时会在 `finally` 中删除两个虚构凭据。
