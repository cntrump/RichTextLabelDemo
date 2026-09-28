//
//  RichTextLabel.swift
//  RichTextKit
//
//  UILabel 的替代品：TextKit 2 排版 + CALayer 绘制 + 可点击 token。
//

import UIKit

// MARK: - 点击事件

public struct TokenTap {
    /// 产生这个 token 的规则标识，例如 `"emoji"`、`"url"`。
    public let identifier: String
    /// 语义值，例如 emoji 名 `"smile"` 或 URL 字符串。
    public let payload: String
    /// token 在**编译后**的 attributed string 里的范围。
    public let range: NSRange

    /// 取出产生它的规则，用来做类型特定的处理。
    public func rule(in registry: TokenRegistry) -> (any TextTokenRule)? {
        registry.rule(forIdentifier: identifier)
    }
}

// MARK: - Label

/// 用 TextKit 2 + CALayer 实现的富文本标签，支持自定义 emoji 图标和可点击 token。
///
/// 与 `UILabel` 的差异：
/// - 内联图标由 `InlineDecoration` 自绘，不受 `NSTextAttachment.image` 的能力限制
///   （异步加载、程序化绘制、后续接动画都可以）。
/// - 任意 token 都能响应点击，不只是 `.link`。
/// - 排版与绘制分离，绘制发生在 `TextDisplayLayer`。
///
/// 用法：
/// ```swift
/// let label = RichTextLabel()
/// label.registry.register(EmojiTokenRule(prefix: "emoji_"))
/// label.registry.register(URLTokenRule())
/// label.onTokenTap = { token in
///     switch token.identifier {
///     case "url":   UIApplication.shared.open(URL(string: token.payload)!)
///     case "emoji": print(" tapped \(token.payload)")
///     default: break
///     }
/// }
/// label.text = "构建成功 :tada: 详见 https://example.com/build/1"
/// ```
public final class RichTextLabel: UIView {
    /// token 规则标识属性 key。
    public static let tokenIDKey = NSAttributedString.Key("RichTextKit.tokenID")
    /// token 语义值属性 key。
    public static let tokenPayloadKey = NSAttributedString.Key("RichTextKit.tokenPayload")

    // MARK: TextKit 2 对象网络

    public let contentStorage = NSTextContentStorage()
    public let layoutManager = NSTextLayoutManager()
    public let textContainer = NSTextContainer(size: .zero)

    /// 规则注册表。在设置 `text` 之前注册。
    public let registry = TokenRegistry()

    private let renderer: RichTextRenderer

    // MARK: Layer

    public override class var layerClass: AnyClass { TextDisplayLayer.self }

    private var displayLayer: TextDisplayLayer {
        layer as! TextDisplayLayer
    }

    // MARK: 外观

    public var font: UIFont = .systemFont(ofSize: 17) {
        didSet { guard font != oldValue else { return }; recompile() }
    }

    public var textColor: UIColor = .label {
        didSet { recompile() }
    }

    public var textInsets: UIEdgeInsets = .zero {
        didSet {
            renderer.insets = textInsets
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    /// 0 表示不限行数。
    public var numberOfLines: Int = 0 {
        didSet {
            textContainer.maximumNumberOfLines = numberOfLines
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    public var lineBreakMode: NSLineBreakMode = .byWordWrapping {
        didSet {
            textContainer.lineBreakMode = lineBreakMode
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    /// Auto Layout 自适应高度时需要告知可用宽度，语义同 `UILabel.preferredMaxLayoutWidth`。
    public var preferredMaxLayoutWidth: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    /// 可选：把排版派发到后台队列（TextKit 2 原生支持）。
    ///
    /// 注意绘制仍在主线程，且异步排版下 `intrinsicContentSize` 首次读取可能拿到估算值，
    /// 需要在排版完成后自行 `invalidateIntrinsicContentSize()`。默认关闭。
    public var layoutQueue: OperationQueue? {
        get { layoutManager.layoutQueue }
        set { layoutManager.layoutQueue = newValue }
    }

    // MARK: 内容

    public private(set) var attributedText: NSAttributedString?

    /// 原始纯文本，用于 `font`/`textColor` 变化后重新编译。
    ///
    /// 必须单独存：编译后的 `attributedText.string` 里 `:party:` 已经变成 U+FFFC，
    /// 拿它再解析一遍会丢掉所有 emoji。
    private var sourceText: String?

    /// 纯文本入口：会经过 `registry` 编译成 attributed string。
    public var text: String? {
        get { sourceText }
        set {
            sourceText = newValue
            guard let newValue, !newValue.isEmpty else {
                setAttributedText(nil)
                return
            }
            setAttributedText(registry.attributedString(from: newValue, baseAttributes: baseAttributes))
        }
    }

    /// 已经构造好的 attributed string 入口（跳过 token 解析）。
    ///
    /// 注意：走这条入口时 `sourceText` 为空，之后改 `font`/`textColor` 不会重新编译内容 ——
    /// 属性由调用方自己掌握。
    public func setAttributedText(_ attributedText: NSAttributedString?) {
        self.attributedText = attributedText
        applyContent()
    }

    /// 用当前 `registry` 重新编译原始文本并重绘。
    ///
    /// 在**设置 `text` 之后**才注册新规则、或异步替换了 emoji 图集时调用。
    public func reload() {
        if sourceText != nil {
            recompile()
        } else {
            displayLayer.setNeedsDisplay()
        }
    }

    /// 点击回调。
    public var onTokenTap: ((TokenTap) -> Void)?

    // MARK: 初始化

    public override init(frame: CGRect) {
        renderer = RichTextRenderer(layoutManager: layoutManager)
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        renderer = RichTextRenderer(layoutManager: layoutManager)
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isUserInteractionEnabled = true
        backgroundColor = .clear
        displayLayer.renderer = renderer
        displayLayer.isOpaque = false
        displayLayer.contentsScale = traitCollection.displayScale

        // 组装 TextKit 2 对象网络。
        // 注意顺序：contentStorage → layoutManager → textContainer，
        // textLayoutManager 在两端都是 weak readonly，只能由这两个 setter 建立连接。
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = textContainer
        textContainer.lineFragmentPadding = 0   // label 不需要默认 5pt 边距
        textContainer.size = CGSize(width: 0, height: Self.unboundedHeight)

        renderer.insets = textInsets
        renderer.contentsScale = traitCollection.displayScale

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
    }

    // MARK: 基础属性

    private var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = lineBreakMode
        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ]
    }

    /// 外观属性变化后，用原始纯文本重新编译。
    ///
    /// 只在通过 `text` 设置过内容时有效；直接用 `setAttributedText(_:)` 传入的
    /// attributed string 由调用方自己掌握属性，这里不会去改它。
    private func recompile() {
        guard let sourceText, !sourceText.isEmpty else { return }
        setAttributedText(registry.attributedString(from: sourceText, baseAttributes: baseAttributes))
    }

    private func applyContent() {
        let newContent = attributedText ?? NSAttributedString(string: "", attributes: baseAttributes)
        contentStorage.performEditingTransaction {
            contentStorage.attributedString = newContent
        }
        // 属性源与写入内容必须是同一个对象，索引才对得上。
        renderer.attributeSource = newContent
        prepareDecorations()
        displayLayer.setNeedsDisplay()
        invalidateIntrinsicContentSize()
    }

    /// 接上 decoration 的重绘回调，并提前启动加载。
    ///
    /// 两点考量：
    /// - `prepare()` 在写入时就调用，而不是等到 `draw`，这样同步 loader 首帧就能画出真图。
    /// - 重绘只 `setNeedsDisplay()`，绝不重新赋值 `attributedText` ——
    ///   后者会触发整篇重排，异步图片一多就明显掉帧。
    private func prepareDecorations() {
        guard let source = renderer.attributeSource, source.length > 0 else { return }
        source.enumerateAttribute(.attachment,
                                  in: NSRange(location: 0, length: source.length)) { value, _, _ in
            guard let attachment = value as? DecorationAttachment else { return }
            attachment.decoration.invalidationHandler = { [weak self] in
                self?.displayLayer.setNeedsDisplay()
            }
            attachment.decoration.prepare()
        }
    }

    // MARK: 布局与尺寸

    public override func layoutSubviews() {
        super.layoutSubviews()
        renderer.insets = textInsets
        renderer.contentsScale = traitCollection.displayScale
        displayLayer.contentsScale = traitCollection.displayScale

        let width = max(0, bounds.width - textInsets.left - textInsets.right)
        if abs(textContainer.size.width - width) > 0.01 {
            textContainer.size = CGSize(width: width, height: Self.unboundedHeight)
            invalidateIntrinsicContentSize()
        }
        displayLayer.setNeedsDisplay()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        let scale = traitCollection.displayScale
        displayLayer.contentsScale = scale
        renderer.contentsScale = scale
        displayLayer.setNeedsDisplay()
    }

    /// 当前文档长度。以 `renderer.attributeSource` 为准，不读 `contentStorage.textStorage`
    /// （独立使用时后者为 nil）。
    private var documentLength: Int { renderer.attributeSource?.length ?? 0 }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard documentLength > 0 else { return .zero }

        let targetWidth = size.width > 0 ? size.width : preferredMaxLayoutWidth
        let unboundedWidth = targetWidth <= 0
        let containerWidth = unboundedWidth
            ? Self.unboundedWidth
            : max(0, targetWidth - textInsets.left - textInsets.right)
        let containerHeight = size.height > 0
            ? max(0, size.height - textInsets.top - textInsets.bottom)
            : Self.unboundedHeight

        textContainer.size = CGSize(width: containerWidth, height: containerHeight)
        layoutManager.ensureLayout(for: contentStorage.documentRange)

        let content = renderer.contentSize()
        return CGSize(width: min(content.width, unboundedWidth ? content.width : targetWidth),
                      height: content.height)
    }

    public override var intrinsicContentSize: CGSize {
        guard documentLength > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
        if preferredMaxLayoutWidth > 0 {
            return sizeThatFits(CGSize(width: preferredMaxLayoutWidth,
                                       height: Self.unboundedHeight))
        }
        return sizeThatFits(CGSize(width: 0, height: Self.unboundedHeight))
    }

    // MARK: 命中测试

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let token = token(at: gesture.location(in: self)) else { return }
        onTokenTap?(token)
    }

    /// 查询某个点上的 token。坐标是 label 自身坐标系。
    ///
    /// 两套坐标系要分清：
    /// - `frameForTextAttachment(at:)` 返回 **fragment** 坐标系
    /// - `enumerateTextSegments` 返回 **text container** 坐标系
    public func token(at point: CGPoint) -> TokenTap? {
        guard let contentManager = layoutManager.textContentManager,
              let source = renderer.attributeSource,
              source.length > 0 else { return nil }

        let documentStart = contentManager.documentRange.location

        // view → container
        let containerPoint = CGPoint(x: point.x - textInsets.left, y: point.y - textInsets.top)
        guard containerPoint.x >= 0, containerPoint.y >= 0,
              let fragment = layoutManager.textLayoutFragment(for: containerPoint) else { return nil }

        let fragmentFrame = fragment.layoutFragmentFrame
        guard fragmentFrame.contains(containerPoint) else { return nil }

        // container → fragment
        let localPoint = CGPoint(x: containerPoint.x - fragmentFrame.minX,
                                 y: containerPoint.y - fragmentFrame.minY)

        // 1) attachment 型 token（emoji 等自绘内容）
        if let nsRange = RichTextLayoutFragment.nsRange(of: fragment.rangeInElement, in: contentManager),
           nsRange.location + nsRange.length <= source.length {
            var found: TokenTap?
            source.enumerateAttribute(.attachment, in: nsRange) { value, range, stop in
                guard found == nil,
                      value is DecorationAttachment,
                      let location = contentManager.location(documentStart,
                                                             offsetBy: range.location) else { return }
                let attachmentFrame = fragment.frameForTextAttachment(at: location)
                guard !attachmentFrame.isNull, !attachmentFrame.isEmpty,
                      attachmentFrame.contains(localPoint) else { return }
                found = makeToken(at: range.location, in: source)
                stop.pointee = true
            }
            if let found { return found }
        }

        // 2) 文字型 token（链接、@提及）：用 text segment 的精确几何做命中
        return textToken(at: containerPoint, in: source, contentManager: contentManager)
    }

    // MARK: Private helpers

    private func textToken(at containerPoint: CGPoint,
                           in source: NSAttributedString,
                           contentManager: NSTextContentManager) -> TokenTap? {
        let documentStart = contentManager.documentRange.location
        let full = NSRange(location: 0, length: source.length)
        var result: TokenTap?

        source.enumerateAttribute(Self.tokenIDKey, in: full) { value, range, stop in
            guard result == nil, value != nil else { return }
            // attachment 型已在上一步处理，跳过
            guard source.attribute(.attachment, at: range.location, effectiveRange: nil) == nil else { return }
            guard let textRange = self.textRange(for: range, from: documentStart, in: contentManager) else { return }

            layoutManager.enumerateTextSegments(in: textRange,
                                                type: .standard,
                                                options: []) { _, segmentFrame, _, _ in
                if segmentFrame.contains(containerPoint) {
                    result = self.makeToken(at: range.location, in: source)
                }
                return result == nil
            }
            if result != nil { stop.pointee = true }
        }
        return result
    }

    private func makeToken(at index: Int, in source: NSAttributedString) -> TokenTap? {
        let full = NSRange(location: 0, length: source.length)
        var effective = NSRange(location: 0, length: 0)
        guard let identifier = source.attribute(Self.tokenIDKey,
                                                at: index,
                                                longestEffectiveRange: &effective,
                                                in: full) as? String else { return nil }
        let payload = (source.attribute(Self.tokenPayloadKey, at: index, effectiveRange: nil) as? String) ?? ""
        return TokenTap(identifier: identifier, payload: payload, range: effective)
    }

    private func textRange(for nsRange: NSRange,
                           from documentStart: any NSTextLocation,
                           in contentManager: NSTextContentManager) -> NSTextRange? {
        guard let start = contentManager.location(documentStart, offsetBy: nsRange.location),
              let end = contentManager.location(documentStart,
                                                offsetBy: nsRange.location + nsRange.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }

    private static let unboundedHeight = CGFloat.greatestFiniteMagnitude
    /// 测单行自然宽度时用大数而不是 greatestFiniteMagnitude，避免 CoreGraphics 出现 NaN。
    private static let unboundedWidth: CGFloat = 1_000_000
}
