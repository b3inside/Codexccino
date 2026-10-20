# 素材说明

## 运行资源

| 文件 | 用途 / 尺寸 | 大小 |
|---|---|---:|
| `Resources/AppIcon.icns` | 应用图标，保留完整 ICNS / Retina 尺寸 | 570,918 B |
| `Resources/Coffee/full.jpg` | 满杯照片，460×340 | 34,810 B |
| `Resources/Coffee/empty.jpg` | 空杯照片，460×340 | 33,066 B |
| `Resources/Coffee/steam.png` | 透明蒸汽，240×300 | 14,982 B |

应用只打包上表中的资源，不包含母版、生成记录或历次预览图。

## 来源与复用

- 图标和杯体照片由项目开发过程中使用的内置 imagegen 生成。图标母版与提示词保存在已提交的 `Assets/AppIcon-master.png` 和 `Assets/AppIcon-prompt.txt`。
- 当前蒸汽采用开发过程中选定并提供的透明 PNG，压缩后用于 1.2.6 及后续版本。
- 杯体采用两张配准照片，液面和表面由 `CoffeeCupView.swift` 裁切合成；13 档共用资源，没有 13 套独立图片。
- 其余生成原稿、外部参考和废弃版本保留在本地 `Assets/` 与 `design/` 中，通过忽略规则排除。后续构建不依赖这些历史文件。
- README 的 `docs/images/preview.jpg` 来自 Codpresso 1.2.9 离线渲染，使用演示数据，已缩小压缩用于文档展示。

## 压缩与重建

图标使用 `scripts/build-icon.sh` 从母版生成标准尺寸，再通过 `scripts/optimize-icon.py` 压缩。16、32、64 像素 PNG 保持原像素；大尺寸保留颜色和边缘透明度的有限调色板，因此不属于无损压缩。母版保留完整像素与透明通道。母版与 ICNS 内嵌 PNG 均移除生成溯源、EXIF、文本等非显示元数据；元数据清理前后所有尺寸的 RGBA 像素逐字节一致。

咖啡照片是压缩 JPEG；蒸汽为透明 PNG。其尺寸与位置参与杯体配准，替换素材时需检查边缘、液面和杯口衔接。液面分档与热气强度位于 `Sources/CodexQuotaCore/CoffeePresentation.swift`。

图标重建的可选依赖见 `requirements-dev.txt`。普通构建只复制现有资源，无需安装 Pillow。

## 当前文件校验值

以下 SHA-256 对应 1.2.8 / build 14 确认素材，便于区分压缩变更与显示逻辑变更。

```text
ebfc9cff7c6e937db8c6b7a557a11d3e058470dee3f89180d0035c65eb084b57  Resources/AppIcon.icns
0b8479895a6dcb59e0f92b8443b6eec9ade1351036e47759d389db6fe80427b6  Resources/Coffee/full.jpg
f1015e95a076ca45cd5392e1af1f20f60895bd4af0c3ae0f5b205698de980189  Resources/Coffee/empty.jpg
841f543b4d86a8838c3d65ce7159fb32765d78a5e858e543ea764fc2e2ae9cef  Resources/Coffee/steam.png
```
