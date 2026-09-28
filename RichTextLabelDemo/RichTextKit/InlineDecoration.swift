//
//  InlineDecoration.swift
//  RichTextKit
//
//  扩展点 1：内联自绘元素。
//  TextKit 2 只负责排版，绘制由我们接管 —— 这是「自定义 emoji 图标」的落点。
//

import UIKit
import CoreGraphics

// MARK: - 布局 / 绘制上下文

/// 计算占位尺寸时可用的信息。
public struct DecorationLayoutContext {
    /// token 所在位置的字体（来自 base attributes）。
    public let font: UIFont
    /// 当前行的候选矩形，宽度是可用行宽。
    public let proposedLineFragment: CGRect

    public init(font: UIFont, proposedLineFragment: CGRect) {
        self.font = font
        self.proposedLineFragment = proposedLineFragment
    }
}

/// 绘制时的状态。
public struct DecorationDrawState {
    public let contentsScale: CGFloat
    public let isHighlighted: Bool

    public init(contentsScale: CGFloat, isHighlighted: Bool = false) {
        self.contentsScale = contentsScale
        self.isHighlighted = isHighlighted
    }
}

// MARK: - 协议

/// 任何能在文本行内自绘的内容。
///
/// 自定义 emoji、等级徽章、内联图片、进度条、代码高亮块都实现这个协议，
/// 不需要改动 `RichTextLabel`。
public protocol InlineDecoration: AnyObject {
    /// 占位矩形。坐标系与 `NSTextAttachment.bounds` 一致：
    /// `origin.y` 相对**基线**，向上为正；`size` 决定行内占位。
    func layoutBounds(in context: DecorationLayoutContext) -> CGRect

    /// 自绘。`frame` 已转换到 layer 坐标系（左上原点，单位 pt），直接画即可。
    func draw(in context: CGContext, frame: CGRect, state: DecorationDrawState)

    /// 内容写入宿主时调用，用来提前启动加载/解码。
    ///
    /// 不要等到 `draw` 里才去加载：那样第一帧必然只能画占位符，
    /// 即使 loader 本身是同步的也要多一次重绘。默认空实现。
    func prepare()

    /// 内容异步变化时（图片下载完成）调用它触发宿主重绘。由 `RichTextLabel` 注入，实现方无需关心。
    var invalidationHandler: (() -> Void)? { get set }
}

extension InlineDecoration {
    public func prepare() {}
}

extension InlineDecoration {
    /// 最常用的对齐方式：垂直居中于文字的 ascender/descender 之间。
    ///
    /// 17pt 系统字体 (ascender ≈ 16.3, descender ≈ -4.1) 配 20pt 图标，
    /// 算出 y ≈ -3.9，视觉上正好居中。
    public static func centeredBounds(size: CGSize, font: UIFont) -> CGRect {
        let visualCenter = (font.ascender + font.descender) / 2
        return CGRect(x: 0,
                      y: visualCenter - size.height / 2,
                      width: size.width,
                      height: size.height)
    }

    /// 底边贴基线（适合「坐在文字行上」的图标）。
    public static func baselineBounds(size: CGSize) -> CGRect {
        CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }
}

// MARK: - 内置实现：图片型装饰

/// 图片装饰，支持同步图、bundle 图和异步加载。
///
/// 异步加载时先画占位块，尺寸**不变**，所以图片到位不会引起重排或跳动。
///
/// `@unchecked Sendable`：加载回调可能来自任意线程，但所有状态修改都在
/// `DispatchQueue.main` 上完成，属于主线程限定（main-thread confined）。
public final class ImageDecoration: InlineDecoration, @unchecked Sendable {
    public var invalidationHandler: (() -> Void)?

    public enum Source {
        /// 立即可用的图片。
        case image(UIImage)
        /// 异步加载。loader 可以在任意线程回调，实现内部会切回主线程。
        case async(loader: (@escaping @Sendable (UIImage?) -> Void) -> Void)
    }

    /// 占位尺寸。布局尺寸固定，不随图片实际大小变化 —— 这是避免行高跳动的关键。
    public let size: CGSize
    public var placeholderColor: UIColor = UIColor.systemGray.withAlphaComponent(0.25)
    public var placeholderCornerRadius: CGFloat = 4

    private let source: Source
    private var resolvedImage: UIImage?
    private var isLoading = false

    public init(size: CGSize, source: Source) {
        self.size = size
        self.source = source
        if case .image(let image) = source {
            self.resolvedImage = image
        }
    }

    public func layoutBounds(in context: DecorationLayoutContext) -> CGRect {
        Self.centeredBounds(size: size, font: context.font)
    }

    public func prepare() {
        loadIfNeeded()
    }

    public func draw(in context: CGContext, frame: CGRect, state: DecorationDrawState) {
        if let image = resolvedImage {
            UIGraphicsPushContext(context)
            image.draw(in: frame)
            UIGraphicsPopContext()
        } else {
            drawPlaceholder(in: context, frame: frame)
            loadIfNeeded()
        }
    }

    // MARK: Private

    private func drawPlaceholder(in context: CGContext, frame: CGRect) {
        UIGraphicsPushContext(context)
        let path = UIBezierPath(roundedRect: frame, cornerRadius: placeholderCornerRadius)
        placeholderColor.setFill()
        path.fill()
        UIGraphicsPopContext()
    }

    private func loadIfNeeded() {
        guard !isLoading, case .async(let loader) = source else { return }
        isLoading = true
        loader { [weak self] image in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                self.resolvedImage = image
                // 只重绘，不重排：占位尺寸从一开始就是最终尺寸。
                self.invalidationHandler?()
            }
        }
    }
}

// MARK: - 承载装饰的 attachment

/// 把 `InlineDecoration` 挂到 attributed string 上的载体。
///
/// 故意**不设置** `image` 和 `bounds`：
/// - 布局尺寸走 `attachmentBounds(...)` 覆写，交给 decoration 决定；
/// - 绘制走 `RichTextLayoutFragment.draw(at:in:)`，由 decoration 自己画。
///
/// 这样 TextKit 2 不会画一遍、我们再画一遍。
final class DecorationAttachment: NSTextAttachment {
    let decoration: any InlineDecoration
    /// 规则标识，用于点击分发。
    let tokenID: String
    /// 语义值，例如 emoji 名 `"smile"` 或 URL 字符串。
    let payload: String

    private let layoutFont: UIFont

    init(decoration: any InlineDecoration,
         tokenID: String,
         payload: String,
         layoutFont: UIFont) {
        self.decoration = decoration
        self.tokenID = tokenID
        self.payload = payload
        self.layoutFont = layoutFont
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func attachmentBounds(for textContainer: NSTextContainer?,
                                   proposedLineFragment lineFrag: CGRect,
                                   glyphPosition position: CGPoint,
                                   characterIndex: Int) -> CGRect {
        decoration.layoutBounds(in: DecorationLayoutContext(font: layoutFont,
                                                            proposedLineFragment: lineFrag))
    }

    override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {
        return nil
    }
}
