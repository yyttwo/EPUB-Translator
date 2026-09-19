# 开源发布前最终报告

审计日期：2026-09-19
候选版本：1.0.1 (4)

这是首次公开 macOS 源码前的历史审计记录，不包含凭据、私人路径、用户 EPUB 或私有 Git 历史。

## 许可证与归属

- 仓库在 `LICENSE` 中包含完整的 GNU Affero General Public License v3.0 原文，SPDX 标识为 `AGPL-3.0-only`。
- 项目归属记录在 `NOTICE` 中，并与 App 元数据一致。
- 未发现需要额外再分发许可的第三方源码、软件包、字体、模型、SDK 或参考截图。
- 自制 EPUB Fixture 包含可读源文件和来源说明。

## 隐私与仓库隔离

- 本地静态扫描未发现真实密钥或私人信息。
- 未包含真实用户 EPUB、运行数据、日志、检查点、数据库、发布二进制、符号链接或硬链接。
- 未复制私有仓库历史、Git 对象替代库或私有远程地址。

## 验证结果

| 门禁 | 结果 |
| --- | --- |
| 单元测试 | 执行 71 项，失败 0 项，跳过 1 项可选外部 Fixture 测试 |
| 界面验收测试 | 7/7 通过 |
| 全新副本安全扫描 | 通过 |
| 全新副本构建 | 通过 |
| 源码提交包含构建产物 | 否 |

## 最终结论

`LICENSE_COMPLIANCE=PASS`
`SECRET_EXPOSURE=0`
`PRIVATE_INFORMATION_EXPOSURE=0`
`PRIVATE_GIT_HISTORY_COPIED=NO`
`READY_FOR_OPEN_SOURCE_PUBLICATION=YES`

该候选随后已按用户确认公开；当前仓库现已扩展为 macOS 与 Windows 统一仓库。
