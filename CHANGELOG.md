# Changelog

本文件记录项目的所有重要变更。
格式参照 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added

- **`RichTextLabel.rendersAsynchronously`**：可选异步渲染开关，直通 `TextDisplayLayer` 对 CALayer `drawsAsynchronously` 的封装，默认关闭
  - 开启后 `TextDisplayLayer.draw(in:)` 录制的 CG 命令**可能**被排队、延后到该方法返回后执行，`display()` 更快返回；许可性语义（头文件用 *may*），系统可以不采纳
  - 画面与关闭时视觉一致（正文逐位相同，彩色内容抗锯齿边缘有 LSB 级色差），收益在主线程耗时；排版与绘制入口仍在主线程，不引入数据竞争
  - 边界：自定义 `InlineDecoration.draw(in:frame:state:)` 不能回读 context；逐帧变化的内容（动画）不适合开
- **演示 App**：`rendersAsynchronously` 开关（④ 异步渲染页），作用到全部演示 label；README「特性」「演示 App」「已知边界」同步更新

### Changed

- **`TextDisplayLayer`**：新增 `rendersAsynchronously` 存储属性（命名避开继承的 `drawsAsynchronously` —— Swift 无法用存储属性覆盖继承属性）；`didSet` 里 `setNeedsDisplay()`，保证运行期切换立即反映到下一次绘制
- **演示 App 结构调整**：`ViewController` 从「单屏四组卡片」改成「feature 列表 + 每个 feature 一个独立子页面」
  - `ViewController`：`insetGrouped` 列表，数据源是 `DemoFeature.all`（标题 / 副标题 / 子页面工厂），点击 push 子页面；新增 feature 只要往数组里追加一项
  - `Features/DemoPageViewController`：子页面公共骨架，原先散在 `ViewController` 里的滚动容器、卡片工厂、`makeDemoLabel()`、字号步进器、点击状态栏都收到这里，子类只写 `buildContent()`
  - `Features/DemoSettings`：字号与异步渲染开关跨子页面共享，任一页面调过对其它页面（含之后新建的）同样生效，`viewWillAppear` 里同步
  - `Features/DemoTokenRules`：演示用规则与图集（`DemoEmoji` / `MentionTokenRule` / `HashtagTokenRule` / `BadgeTokenRule` / `BadgeDecoration`）从 `ViewController.swift` 移出，改为 internal 供各页面共用
  - 四个子页面：`EmojiDemoViewController` / `TextTokenDemoViewController` / `BadgeDemoViewController` / `AsyncRenderingDemoViewController`；④ 页原本只靠其它卡片的 label 当作用对象，现在自带一张 emoji + 链接 + @提及 + 徽章的混合 label
  - `Main.storyboard`：`ViewController` 包进 `UINavigationController` 作为 initial view controller，子页面用 push 导航
  - RichTextKit 库代码未改动；README「目录结构」「演示 App」同步更新

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
