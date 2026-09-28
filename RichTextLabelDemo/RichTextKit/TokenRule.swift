//
//  TokenRule.swift
//  RichTextKit
//
//  扩展点 2：从纯文本里识别 token。
//  注册一条规则就能让 RichTextLabel 支持一种新的内联内容，无需改 label 本身。
//

import UIKit

// MARK: - 匹配结果

public struct TokenMatch: Equatable {
    /// 在原始纯文本中的范围。
    public let range: NSRange
    /// 原始文本，例如 `":smile:"`、`"https://a.com"`、`"@alice"`。
    public let text: String
    /// 语义值，例如 `"smile"`、`"alice"`。
    public let value: String

    public init(range: NSRange, text: String, value: String) {
        self.range = range
        self.text = text
        self.value = value
    }
}

// MARK: - 规则协议

/// 一条 token 规则 = 识别 + （可选）自绘 + （可选）附加属性。
///
/// 两种产出形态：
/// - `decoration(for:)` 返回非 nil → 该 token 被替换成一个 attachment 字符，
///   由 decoration 自绘。适合 emoji、徽章、图片。
/// - 返回 nil → 保留原文字，只叠加 `attributes(for:)`。适合链接、@提及、话题标签。
public protocol TextTokenRule {
    /// 唯一标识，用于点击事件分发。
    var identifier: String { get }

    /// 扫描纯文本，返回匹配。顺序不限，注册表会排序并解决重叠。
    func matches(in text: String) -> [TokenMatch]

    /// 生成内联绘制对象。返回 nil 表示该 token 仍按文字渲染。
    func decoration(for match: TokenMatch, font: UIFont) -> (any InlineDecoration)?

    /// 非 attachment 型 token 要叠加的属性。
    func attributes(for match: TokenMatch) -> [NSAttributedString.Key: Any]
}

extension TextTokenRule {
    public func decoration(for match: TokenMatch, font: UIFont) -> (any InlineDecoration)? { nil }
    public func attributes(for match: TokenMatch) -> [NSAttributedString.Key: Any] { [:] }
}

// MARK: - 注册表

/// 规则注册表，同时负责把纯文本编译成 attributed string。
public final class TokenRegistry {
    private var rules: [any TextTokenRule] = []

    public init() {}

    public init(rules: [any TextTokenRule]) {
        rules.forEach(register)
    }

    /// 注册顺序即优先级：区间重叠时，先注册的规则胜出。
    public func register(_ rule: any TextTokenRule) {
        rules.removeAll { $0.identifier == rule.identifier }
        rules.append(rule)
    }

    public func rule(forIdentifier identifier: String) -> (any TextTokenRule)? {
        rules.first { $0.identifier == identifier }
    }

    /// 把纯文本编译成 attributed string。
    ///
    /// 关键实现点：attachment 型 token 被替换成**单个** `U+FFFC` 字符，
    /// 所以光标移动和删除天然是原子的 —— 一次退格删掉整个 emoji。
    public func attributedString(from text: String,
                                 baseAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        guard !text.isEmpty else { return NSAttributedString(string: "", attributes: baseAttributes) }

        let ns = text as NSString
        let font = (baseAttributes[.font] as? UIFont) ?? .systemFont(ofSize: 17)

        // 1. 收集所有匹配，按位置排序，剔除重叠（保留先注册/更靠前的）
        var hits: [(match: TokenMatch, rule: any TextTokenRule)] = []
        for rule in rules {
            for match in rule.matches(in: text) where match.range.length > 0 {
                hits.append((match, rule))
            }
        }
        hits.sort { $0.match.range.location < $1.match.range.location }

        var accepted: [(match: TokenMatch, rule: any TextTokenRule)] = []
        var lastEnd = 0
        for hit in hits where hit.match.range.location >= lastEnd {
            accepted.append(hit)
            lastEnd = hit.match.range.location + hit.match.range.length
        }

        // 2. 分段拼装
        let result = NSMutableAttributedString()
        var cursor = 0

        func appendPlain(_ range: NSRange) {
            guard range.length > 0 else { return }
            result.append(NSAttributedString(string: ns.substring(with: range), attributes: baseAttributes))
        }

        for hit in accepted {
            appendPlain(NSRange(location: cursor, length: hit.match.range.location - cursor))

            if let decoration = hit.rule.decoration(for: hit.match, font: font) {
                let attachment = DecorationAttachment(decoration: decoration,
                                                      tokenID: hit.rule.identifier,
                                                      payload: hit.match.value,
                                                      layoutFont: font)
                var attrs = baseAttributes
                attrs[.attachment] = attachment
                attrs[RichTextLabel.tokenIDKey] = hit.rule.identifier
                attrs[RichTextLabel.tokenPayloadKey] = hit.match.value
                // U+FFFC == NSAttachmentCharacter
                result.append(NSAttributedString(string: "\u{FFFC}", attributes: attrs))
            } else {
                let piece = NSMutableAttributedString(string: ns.substring(with: hit.match.range),
                                                      attributes: baseAttributes)
                let full = NSRange(location: 0, length: piece.length)
                piece.addAttributes(hit.rule.attributes(for: hit.match), range: full)
                piece.addAttributes([
                    RichTextLabel.tokenIDKey: hit.rule.identifier,
                    RichTextLabel.tokenPayloadKey: hit.match.value,
                ], range: full)
                result.append(piece)
            }

            cursor = hit.match.range.location + hit.match.range.length
        }

        appendPlain(NSRange(location: cursor, length: ns.length - cursor))
        return result
    }
}

// MARK: - 内置规则：自定义 emoji

/// 识别 `:emoji_name:` 形式的自定义表情。
public final class EmojiTokenRule: TextTokenRule {
    public let identifier = "emoji"

    public typealias Loader = (String, @escaping @Sendable (UIImage?) -> Void) -> Void

    /// 表情名是否已知。返回 false 时保留原文本（避免把 `:not_an_emoji:` 变成空白占位）。
    /// 传 nil 表示一律当作有效 emoji，未加载完成时显示占位块。
    public var isKnownName: ((String) -> Bool)?

    /// 固定占位尺寸。nil 表示按字号自动推算。
    public var size: CGSize?
    /// `size` 为 nil 时，边长 = 字号 × 该倍率。
    public var sizeRatioToFont: CGFloat

    private let pattern: NSRegularExpression
    private let loader: Loader

    /// - Parameters:
    ///   - size: 固定占位尺寸；传 nil 则跟随字号。
    ///   - sizeRatioToFont: 跟随字号时的边长倍率。
    ///   - isKnownName: 可选的存在性校验，返回 false 的 token 保留原文。
    ///   - loader: 按名字取图。同步实现（如 `UIImage(named:)`）直接在回调里返回即可。
    public init(size: CGSize? = nil,
                sizeRatioToFont: CGFloat = 1.2,
                isKnownName: ((String) -> Bool)? = nil,
                loader: @escaping Loader) {
        self.size = size
        self.sizeRatioToFont = sizeRatioToFont
        self.isKnownName = isKnownName
        self.loader = loader
        // :name: —— 名字允许字母数字、下划线、加号、减号
        self.pattern = try! NSRegularExpression(pattern: ":([a-zA-Z0-9_+\\-]+):")
    }

    /// 从 asset catalog 加载的便捷构造。
    public convenience init(prefix: String = "emoji_",
                            size: CGSize? = nil,
                            bundle: Bundle? = nil) {
        self.init(size: size, loader: { name, completion in
            completion(UIImage(named: prefix + name, in: bundle, compatibleWith: nil))
        })
    }

    public func matches(in text: String) -> [TokenMatch] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        return pattern.matches(in: text, range: full).compactMap { result in
            guard result.numberOfRanges > 1 else { return nil }
            let name = ns.substring(with: result.range(at: 1))
            guard isKnownName?(name) ?? true else { return nil }
            return TokenMatch(range: result.range,
                              text: ns.substring(with: result.range),
                              value: name)
        }
    }

    public func decoration(for match: TokenMatch, font: UIFont) -> (any InlineDecoration)? {
        let resolved = size ?? CGSize(width: round(font.pointSize * sizeRatioToFont),
                                      height: round(font.pointSize * sizeRatioToFont))
        let name = match.value
        let loader = self.loader
        return ImageDecoration(size: resolved, source: .async { completion in
            loader(name, completion)
        })
    }
}

// MARK: - 内置规则：URL

/// 用 `NSDataDetector` 识别 URL，保留文字形态，叠加 `.link` 属性。
public final class URLTokenRule: TextTokenRule {
    public let identifier = "url"

    public var linkAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: UIColor.systemBlue,
        .underlineStyle: NSUnderlineStyle.single.rawValue,
    ]

    private let detector: NSDataDetector?

    public init() {
        self.detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }

    public func matches(in text: String) -> [TokenMatch] {
        guard let detector else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        return detector.matches(in: text, range: full).compactMap { result in
            guard let url = result.url else { return nil }
            return TokenMatch(range: result.range,
                              text: ns.substring(with: result.range),
                              value: url.absoluteString)
        }
    }

    public func attributes(for match: TokenMatch) -> [NSAttributedString.Key: Any] {
        var attrs = linkAttributes
        if let url = URL(string: match.value) {
            attrs[.link] = url
        }
        return attrs
    }
}
