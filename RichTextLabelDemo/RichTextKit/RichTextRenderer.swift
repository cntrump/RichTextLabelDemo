//
//  RichTextRenderer.swift
//  RichTextKit
//
//  TextKit 2 对象网络 + CALayer 绘制。
//  排版完全交给 TextKit 2，我们只做两件事：vending 自定义 fragment、在 fragment 里补画 decoration。
//

import UIKit
import CoreGraphics

// MARK: - 自定义 layout fragment

/// 先用 TextKit 2 画文字，再把 `InlineDecoration` 画到 attachment 的位置上。
///
/// 位置来源是 `NSTextLayoutFragment.frameForTextAttachment(at:)` ——
/// 它直接返回 attachment 在 fragment 坐标系里的矩形，
/// 省掉自己从 line fragment 推算基线和字形偏移的麻烦。
final class RichTextLayoutFragment: NSTextLayoutFragment {
    /// vending 时由 renderer 注入，用来查属性。
    weak var renderer: RichTextRenderer?

    var contentsScale: CGFloat = 1
    var isHighlighted: Bool = false

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        drawDecorations(at: point, in: context)
    }

    // MARK: Private

    private func drawDecorations(at point: CGPoint, in context: CGContext) {
        guard state == .layoutAvailable,
              let renderer,
              let source = renderer.attributeSource,
              let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return }

        guard let nsRange = Self.nsRange(of: rangeInElement, in: contentManager),
              nsRange.location + nsRange.length <= source.length else { return }

        let documentStart = contentManager.documentRange.location
        let drawState = DecorationDrawState(contentsScale: contentsScale, isHighlighted: isHighlighted)

        source.enumerateAttribute(.attachment, in: nsRange) { value, range, _ in
            guard let attachment = value as? DecorationAttachment,
                  let location = contentManager.location(documentStart,
                                                         offsetBy: range.location) else { return }

            let frame = frameForTextAttachment(at: location)
            guard !frame.isNull, !frame.isEmpty else { return }

            attachment.decoration.draw(in: context,
                                       frame: frame.offsetBy(dx: point.x, dy: point.y),
                                       state: drawState)
        }
    }

    /// 把 document 坐标系的 `NSTextRange` 转成属性字符串的 `NSRange`。
    static func nsRange(of textRange: NSTextRange, in contentManager: NSTextContentManager) -> NSRange? {
        let documentStart = contentManager.documentRange.location
        let location = contentManager.offset(from: documentStart, to: textRange.location)
        let length = contentManager.offset(from: textRange.location, to: textRange.endLocation)
        guard location != NSNotFound, length != NSNotFound, location >= 0, length >= 0 else { return nil }
        return NSRange(location: location, length: length)
    }
}

// MARK: - Renderer

/// 持有 TextKit 2 对象网络，负责把整篇文档画进一个 CGContext。
///
/// 同时充当 `NSTextLayoutManagerDelegate`，为每个 element 返回自定义 fragment。
final class RichTextRenderer: NSObject {
    let layoutManager: NSTextLayoutManager

    /// 属性查询的唯一来源，由 `RichTextLabel` 在写入内容时同步设置。
    ///
    /// 为什么不用 `NSTextContentStorage.textStorage`：
    /// 独立构造 `NSTextContentStorage`（非 UITextView 托管）时，即使设过 `attributedString`，
    /// `textStorage` 仍然是 nil —— 它不会自动创建后备存储。
    /// 为什么不用 `contentStorage.attributedString`：
    /// 那是 `copy` 语义的属性，每帧绘制都拷一份整篇文档。
    ///
    /// 这里持有的正是写进 contentStorage 的那个对象，字符索引与文档一一对应。
    var attributeSource: NSAttributedString?

    /// 文本相对 layer 原点的内缩，绘制和命中测试都要用它换算坐标。
    var insets: UIEdgeInsets = .zero
    var contentsScale: CGFloat = 1
    var isHighlighted: Bool = false

    init(layoutManager: NSTextLayoutManager) {
        self.layoutManager = layoutManager
        super.init()
        layoutManager.delegate = self
    }

    /// 绘制全部内容。
    ///
    /// 没有走 `NSTextViewportLayoutController`：label 是非滚动的，内容全量可见，
    /// 直接枚举所有 fragment 比维护 viewport 平铺更简单。
    /// 如果要用在滚动容器里做长文档，换成 viewport controller 才能拿到惰性布局的收益。
    func draw(in context: CGContext) {
        guard let contentManager = layoutManager.textContentManager else { return }

        layoutManager.ensureLayout(for: contentManager.documentRange)

        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { [weak self] fragment in
            guard let self else { return true }

            if let rich = fragment as? RichTextLayoutFragment {
                rich.contentsScale = self.contentsScale
                rich.isHighlighted = self.isHighlighted
            }

            let frame = fragment.layoutFragmentFrame
            // layoutFragmentFrame 在 text container 坐标系；加上 insets 得到 layer 坐标系。
            let origin = CGPoint(x: frame.minX + self.insets.left,
                                 y: frame.minY + self.insets.top)
            fragment.draw(at: origin, in: context)
            return true
        }
    }

    /// 内容尺寸（含 insets），供 `sizeThatFits` / `intrinsicContentSize` 使用。
    func contentSize() -> CGSize {
        let used = layoutManager.usageBoundsForTextContainer
        return CGSize(width: ceil(used.width) + insets.left + insets.right,
                      height: ceil(used.height) + insets.top + insets.bottom)
    }
}

extension RichTextRenderer: NSTextLayoutManagerDelegate {
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager,
                           textLayoutFragmentFor location: any NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        let fragment = RichTextLayoutFragment(textElement: textElement, range: nil)
        fragment.renderer = self
        fragment.contentsScale = contentsScale
        return fragment
    }
}

// MARK: - Layer

/// 承载绘制的 CALayer。
///
/// 用 layer 而不是 `UIView.draw(_:)`，是为了让绘制和视图解耦：
/// 同一个 renderer 可以驱动多个 layer（例如高亮层和文本层分离），
/// 也便于接入异步渲染（见 `rendersAsynchronously`）。
final class TextDisplayLayer: CALayer {
    weak var renderer: RichTextRenderer?

    /// 是否异步渲染。默认 `false`，即绘制命令在 `draw(in:)` 返回前同步执行完毕。
    ///
    /// 开启后直通 CALayer 的 `drawsAsynchronously`：`draw(in:)` 收到的 `CGContext`
    /// **可能**把提交给它的绘制命令排队，等本方法返回之后再执行
    /// （头文件用的是 *may queue*，许可性语义，系统可以不采纳）。
    /// 收益是绘制量大时 `display()` 更快返回，代价是内容上屏时机可能延后。
    ///
    /// 被延后的**只有 CG 命令的执行**，`draw(in:)` 本身仍在主线程同步跑完 ——
    /// 所以 `ensureLayout`、fragment 上的 `contentsScale` / `isHighlighted` 写入、
    /// `ImageDecoration` 未命中图片时触发的加载，都还在主线程，不引入新的数据竞争。
    /// 前提是绘制路径不回读 context（`CGBitmapContextGetData` /
    /// `UIGraphicsGetImageFromCurrentImageContext` 之类）：命令延后执行时回读只能拿到空数据。
    ///
    /// 命名不用 `drawsAsynchronously`：那是继承来的属性，Swift 子类无法用存储属性覆盖它。
    var rendersAsynchronously: Bool = false {
        didSet {
            guard rendersAsynchronously != oldValue else { return }
            drawsAsynchronously = rendersAsynchronously
            // 开关只对「之后发生的那次绘制」生效。layer 不脏的话光改 flag 什么都不会变，
            // 运行期切换会看起来毫无反应。
            setNeedsDisplay()
        }
    }

    override func draw(in context: CGContext) {
        renderer?.draw(in: context)
    }
}
