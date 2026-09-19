# 参与贡献

感谢您帮助改进 EPUB翻译。

## 提交变更前

1. 先创建 Issue，说明问题、预期行为和影响范围。
2. 不要提交真实 API Key、用户 EPUB、书籍摘录、私人路径、日志、检查点或构建产物。
3. 新增测试资料必须完全自创、体积小，并在 `fixtures/` 中记录来源。
4. 不得新增依赖本机绝对路径、私有仓库或未声明的第三方代码与素材。
5. 涉及 API Key 保存方式的变更必须先经过明确的安全与产品评审。

Swift 和 C# 代码请延续现有命名与缩进风格，优先使用小而明确的类型和函数。界面变更需保留辅助功能标识，并补充相应测试。

## 验证

macOS：

```bash
./scripts/security-scan.sh
./scripts/build.sh
./scripts/test.sh
./scripts/test-ui.sh
```

Windows 构建与测试说明见 [`app/windows/README.md`](app/windows/README.md)。

提交 Pull Request 时，请填写模板中的隐私、许可证、测试和 EPUB 格式保留检查项。

## 许可证

本项目采用 GNU Affero General Public License v3.0（`AGPL-3.0-only`）。除非您明确另行说明，您有意提交并被项目接收的贡献将按相同的 AGPL v3 条款提供；已有单独书面贡献协议的，以该协议为准。
