# 测试 Fixture

`stage-1-self-authored.epub` 是本项目完全自创的最小 EPUB 测试资料，不含用户书籍、受版权保护的摘录或个人信息。

可读源文件位于 `stage-1-source/`。修改源文件后运行：

```bash
./scripts/create-fixture.sh
```

生成脚本会确保 EPUB 要求的 `mimetype` 条目位于压缩包首位且不压缩。
