# Stage 1 tests

`EPUBTranslator.Core.Tests` covers the four stable translation modes, Provider IDs, credential abstraction with fake secrets, extension/path policy, output-source separation, errors and the fixed support URL.

`EPUBTranslator.Windows.Tests` covers AppData directory policy, file-copy behavior and an opt-in Credential Manager integration test. Windows-only tests must run on a real Windows 11 x64 environment.

The credential integration test uses only `FAKE_QWEN_SECRET` and `FAKE_DEEPSEEK_SECRET`. It is disabled unless `EPUB_TRANSLATOR_RUN_CREDENTIAL_TESTS=1` is set, and deletes both fake credentials in a `finally` block.
