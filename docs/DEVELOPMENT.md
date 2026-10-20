# 开发与检查

所有命令在项目根目录执行。应用当前版本为 1.2.8 / build 14。

## 构建

```sh
bash scripts/test.sh
bash scripts/build.sh
bash scripts/launch.sh
```

- `test.sh` 在需要时补充 Command Line Tools 中的 Swift Testing 插件路径。
- `build.sh` 构建 Release，暂存完整应用包，剥离包内程序的调试 / 本地符号，再进行 ad-hoc 签名和严格检查，最后替换 `dist/Codex用量.app`。
- 未剥离的程序留在 `.build/`。构建失败不会先覆盖已有应用包。
- `launch.sh` 使用 Launch Services，程序不依赖终端会话；已有实例运行时会唤起该实例。

## 只读连接检查

```sh
"dist/Codex用量.app/Contents/MacOS/CodexMenuBar" --check
```

这个命令会连接本机 Codex CLI、读取真实用量并退出，不执行重置。输出含真实用量，不应作为仓库素材提交。

## 离线界面与交互

```sh
"dist/Codex用量.app/Contents/MacOS/CodexMenuBar" --preview 62
"dist/Codex用量.app/Contents/MacOS/CodexMenuBar" --render-previews "$PWD/.build/qa/previews"
"dist/Codex用量.app/Contents/MacOS/CodexMenuBar" --verify-cancel "$PWD/.build/qa/cancellation"
"dist/Codex用量.app/Contents/MacOS/CodexMenuBar" --verify-toggle "$PWD/.build/qa/toggle"
```

这些模式使用离线服务，不连接账户，也不读取真实重置记录。取消检查覆盖取消按钮、默认回车、中止关闭和待确认重试取消；要求消费请求为 0、次数和历史文件不变。

预览还支持 `unknown`、`error`、`stale`、`multiple`、`no-credits`、`no-account`、`uncertain`。全状态渲染输出 20 张原生画面。菜单栏回归检查 8 个展开、收起和焦点状态，属于原生按钮动作与事件顺序注入，不是外部鼠标自动化。

单独运行取消或切换回归时，先退出正常实例，以免其他卡片干扰模态和焦点判断。

## 真实启动回归

先完成构建，再运行：

```sh
swiftc -parse-as-library scripts/verify-launch.swift -o .build/verify-launch
.build/verify-launch "$PWD/dist/Codex用量.app" "$PWD/.build/qa/launch"
```

启动检查会正常退出已有 Codexccino 实例，再通过 Launch Services 启动待测包，验证：

- 冷启动后菜单栏按钮就绪，卡片默认收起。
- Finder 等效重开显示已有卡片。
- 直接启动另一副本会唤起原实例，始终只保留一个进程。
- 卡片在屏幕上，启动器返回后进程仍运行。

此检查使用生产服务正常读取用量，不会点击续杯或执行重置。报告仅记录进程和窗口状态，不记录账户标识或重置历史。检查结束后应用仍运行；如需回到已安装版本，先退出测试实例再打开“应用程序”中的副本。

## 图标重建

普通构建只复制已提交的 `Resources/AppIcon.icns`，无需安装 Python 图像依赖。仅重新生成图标时需要：

```sh
python3 -m pip install -r requirements-dev.txt
bash scripts/build-icon.sh
```

脚本从已提交的 `Assets/AppIcon-master.png` 生成完整图标尺寸，再运行 `optimize-icon.py`。小尺寸 PNG 保持原像素，大尺寸轻度量化颜色与边缘透明度；全部尺寸过滤 EXIF、文本和生成溯源元数据。参见[素材说明](ASSETS.md)。

## 发布包

源码提交不包含 `.build/`、`dist/`、设计历史或本机检查输出。构建生成的应用和 ZIP 应单独放入仓库 Release 附件。

发布前至少检查应用版本 / 构建号、严格签名、解压后的执行权限与启动结果。若制作 ZIP，应保留 UTF-8 文件名和可执行权限；不要将未剥离二进制或图标原稿放入应用包。
