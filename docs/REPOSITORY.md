# 提交范围

当前应用名称为 **Codpresso**，确认版本为 **1.2.9 / build 15**。

当前提交范围共 **40 个文件，约 2.16 MB**。本轮对 1.2.9 / build 15 完成 26 项测试、Release 构建、原生取消 / 菜单栏 / 启动检查，以及安装包严格签名检查；图标移除元数据后全部尺寸像素保持一致。

## 需要提交

| 路径 | 用途 |
|---|---|
| `Sources/`、`Tests/` | 应用 / 核心逻辑及测试 |
| `Package.swift`、`Info.plist` | Swift 包、应用版本和配置 |
| `Resources/` | 运行必需的压缩图标、杯体照片与蒸汽 |
| `scripts/`、`requirements-dev.txt` | 构建、启动、验证和可选图标重建 |
| `Assets/AppIcon-master.png`、`Assets/AppIcon-prompt.txt` | 图标重建所需的可编辑母版与生成提示词 |
| `README.md`、`CHANGELOG.md`、`docs/` | 使用、开发、验证、素材和提交说明 |
| `.gitignore`、`.gitattributes` | 忽略范围、文本换行和二进制属性 |

普通构建只依赖已提交文件，不依赖本地设计草稿或旧安装包。

## 保留本地，不提交

| 路径 | 原因 |
|---|---|
| `.build/`、`.swiftpm/` | 构建缓存、未剥离程序和 SwiftPM 工作区状态 |
| `dist/` | 生成的应用、当前与历史 ZIP；应作为 Release 附件分发 |
| `design/`、`design-qa.md` | 设计尝试、历次截图、安装 / 启动报告和机器路径 |
| `Assets/` 中的其他文件 | 多轮生成原稿、外部参考、旧图标与素材备份，非构建依赖 |
| 本机工具配置、环境文件、系统临时文件 | 不属于共享项目配置 |
| `auth.json`、`reset-history.json` 及其副本 | 登录数据与账户操作历史 |

上述内容通过 `.gitignore` 排除，原文件保留。当前运行资源在 `Resources/` 中，不能一起忽略。仓库不需要 Git LFS 即可保存目前保留的单个文件。

## GitHub 仓库

- 仓库地址和所属账号以当前 GitHub 页面为准，文档不硬编码个人账号。
- 默认分支：`main`，远程名称：`origin`。
- 创建时采用私有可见性。
- 应用和安装包为 1.2.9 / build 15；当前未添加开源许可证。
- 提交作者和标签作者统一采用项目身份，初始历史与当前版本标签均使用清理后的内容。
- 清理前的本地恢复备份保留在被忽略的设计目录中，不推送；其他已有克隆不得合并回旧历史。

日常提交前可检查：

```sh
git status --short --untracked-files=all
git status --short --ignored
```

确认待提交文件符合上表。若文件已被跟踪，`.gitignore` 不会自动取消跟踪，应单独检查索引。历史安装包可在后续发布 Release 时作为附件上传，不进入源码提交。
