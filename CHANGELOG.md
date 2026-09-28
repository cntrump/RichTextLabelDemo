# Changelog

本文件记录项目的所有重要变更。
格式参照 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.0.0] - 2026-09-28

首个版本：RichTextKit 核心库 + 演示 App + 项目文档。全部代码与文档由 AI（Claude Code）编写，没有人类参与（见 README 声明）。

### Added

- **`RichTextLabel`**：基于 TextKit 2 排版 + `TextDisplayLayer`（CALayer）绘制的 `UILabel` 替代品
  - 任意 token 可点击：`onTokenTap` 回调携带 `identifier` / `payload` / `range`；命中测试区分 attachment 型（`frameForTextAttachment(at:)`，fragment 坐标系）与文字型（`enumerateTextSegments`，container 坐标系）
  - Auto Layout 支持：`intrinsicContentSize` / `sizeThatFits(_:)` / `preferredMaxLayoutWidth`
  - 外观属性：`font` / `textColor` 变化后用原始纯文本自动重新编译；`textInsets` / `numberOfLines` / `lineBreakMode`
  - 可选后台排版（`layoutQueue`），排版与绘制分离
- **扩展点① `InlineDecoration`**：内联自绘协议（`layoutBounds` / `draw` / `prepare` / `invalidationHandler`）
  - 内置 `ImageDecoration`：同步图与任意线程回调的异步加载；占位尺寸即最终尺寸，图片到位只重绘不重排，行高不跳动
  - `DecorationAttachment`：attachment 型 token 替换成**单个** `U+FFFC`，光标移动与删除天然原子
  - 便捷对齐：`centeredBounds(size:font:)` / `baselineBounds(size:)`
- **扩展点② `TextTokenRule` + `TokenRegistry`**：注册一条规则即支持一种新的内联内容，无需改 label
  - 纯文本 → attributed string 编译：匹配排序、重叠剔除，注册顺序即优先级
  - 内置 `EmojiTokenRule`：识别 `:name:`，`isKnownName` 校验失败保留原文，尺寸默认跟随字号（`sizeRatioToFont = 1.2`）
  - 内置 `URLTokenRule`：`NSDataDetector` 识别，叠加 `.link` 属性 + 链接样式
  - 支持设置 `text` 之后注册新规则，`reload()` 热生效
- **演示 App**（`ViewController`）：三组示例 + 全局交互
  - ① 自定义 emoji：异步 loader 模拟 0.8s 网络延迟（占位块 → 真图），未注册名字保留原文；无图片资源，emoji 由代码现场渲染
  - ② 文字型 token：URL（点击直接打开）、`@提及` 自定义规则；按钮演示运行期注册 `#话题` 规则 + `reload()`
  - ③ 自绘徽章：`BadgeTokenRule` + `BadgeDecoration` 纯 CoreGraphics 绘制胶囊徽章
  - 字号步进器（13–24pt）演示外观变化触发重编译；底部状态栏显示最近一次点击的 token 信息
- **文档**：`README.md`（架构、数据流、两个扩展点的用法与边界、AI 编写声明）、`CHANGELOG.md`

[1.0.0]: https://github.com/cntrump/RichTextLabelDemo/releases/tag/v1.0.0
