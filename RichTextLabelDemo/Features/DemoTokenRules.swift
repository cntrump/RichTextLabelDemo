//
//  DemoTokenRules.swift
//  RichTextLabelDemo
//
//  Created by v on 9/29/26.
//
//  演示用的 token 规则与图集，被各个 feature 子页面共用：
//  DemoEmoji（① ④）、MentionTokenRule / HashtagTokenRule（②）、BadgeTokenRule + BadgeDecoration（③ ④）。
//

import UIKit

// MARK: - 演示用 emoji 图集

/// 没有图片资源也能演示：把系统 unicode emoji 现渲染成图，充当「自定义表情图集」。
/// 真实项目里换成 `EmojiTokenRule(prefix:)` 从 asset catalog 加载即可。
enum DemoEmoji {
    static let unicode: [String: String] = [
        "tada": "🎉",
        "rocket": "🚀",
        "fire": "🔥",
        "eyes": "👀",
        "smile": "😄",
        "heart": "❤️",
    ]

    static func render(_ emoji: String, side: CGFloat = 64) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: side * 0.82)]
            let text = emoji as NSString
            let textSize = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (side - textSize.width) / 2,
                                  y: (side - textSize.height) / 2),
                      withAttributes: attrs)
        }
    }

    /// 演示用的 emoji 规则：loader 模拟网络延迟，期间由 `ImageDecoration` 画占位块。
    static func tokenRule(delay: TimeInterval = 0.8) -> EmojiTokenRule {
        EmojiTokenRule(
            isKnownName: { DemoEmoji.unicode[$0] != nil },
            loader: { name, completion in
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    completion(DemoEmoji.unicode[name].map { DemoEmoji.render($0) })
                }
            })
    }
}

// MARK: - 演示用 token 规则

/// @提及：文字型 token，只叠属性，不产生 attachment。
final class MentionTokenRule: TextTokenRule {
    let identifier = "mention"

    private let pattern = try! NSRegularExpression(pattern: "@([A-Za-z0-9_]+)")

    func matches(in text: String) -> [TokenMatch] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        return pattern.matches(in: text, range: full).map { result in
            TokenMatch(range: result.range,
                       text: ns.substring(with: result.range),
                       value: ns.substring(with: result.range(at: 1)))
        }
    }

    func attributes(for match: TokenMatch) -> [NSAttributedString.Key: Any] {
        [.foregroundColor: UIColor.systemPurple]
    }
}

/// #话题：演示「设置 text 之后」再注册规则，配合 label.reload() 生效。
final class HashtagTokenRule: TextTokenRule {
    let identifier = "hashtag"

    private let pattern = try! NSRegularExpression(pattern: "#([A-Za-z0-9_]+)")

    func matches(in text: String) -> [TokenMatch] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        return pattern.matches(in: text, range: full).map { result in
            TokenMatch(range: result.range,
                       text: ns.substring(with: result.range),
                       value: ns.substring(with: result.range(at: 1)))
        }
    }

    func attributes(for match: TokenMatch) -> [NSAttributedString.Key: Any] {
        [.foregroundColor: UIColor.systemGreen]
    }
}

/// [name] 徽章：attachment 型 token，decoration 纯代码绘制。
final class BadgeTokenRule: TextTokenRule {
    let identifier = "badge"

    private let colors: [String: UIColor] = [
        "vip": .systemOrange,
        "beta": .systemTeal,
        "new": .systemPink,
    ]
    private let pattern = try! NSRegularExpression(pattern: "\\[([A-Za-z]+)\\]")

    func matches(in text: String) -> [TokenMatch] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        return pattern.matches(in: text, range: full).compactMap { result in
            let value = ns.substring(with: result.range(at: 1))
            // 未登记的名字保留原文，避免把普通方括号内容吞掉。
            guard colors[value.lowercased()] != nil else { return nil }
            return TokenMatch(range: result.range,
                              text: ns.substring(with: result.range),
                              value: value)
        }
    }

    func decoration(for match: TokenMatch, font: UIFont) -> (any InlineDecoration)? {
        BadgeDecoration(text: match.value.uppercased(),
                        tintColor: colors[match.value.lowercased()] ?? .systemGray,
                        font: font)
    }
}

/// 内联徽章：圆角胶囊 + 描边 + 文字，展示 InlineDecoration 的自绘能力。
/// 尺寸在 init 里按基准字号算好，layoutBounds 只做垂直居中 —— 占位固定，绘制内容随便换。
final class BadgeDecoration: InlineDecoration {
    var invalidationHandler: (() -> Void)?

    private let text: String
    private let tintColor: UIColor
    private let size: CGSize

    init(text: String, tintColor: UIColor, font: UIFont) {
        self.text = text
        self.tintColor = tintColor
        let textFont = UIFont.systemFont(ofSize: round(font.pointSize * 0.6), weight: .semibold)
        let textSize = (text as NSString).size(withAttributes: [.font: textFont])
        let height = round(font.pointSize * 1.15)
        self.size = CGSize(width: ceil(textSize.width) + height * 0.8, height: height)
    }

    func layoutBounds(in context: DecorationLayoutContext) -> CGRect {
        Self.centeredBounds(size: size, font: context.font)
    }

    func draw(in context: CGContext, frame: CGRect, state: DecorationDrawState) {
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        let capsule = UIBezierPath(roundedRect: frame, cornerRadius: frame.height / 2)
        tintColor.withAlphaComponent(0.15).setFill()
        capsule.fill()
        tintColor.withAlphaComponent(0.6).setStroke()
        capsule.lineWidth = 1
        capsule.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: frame.height * 0.52, weight: .semibold),
            .foregroundColor: tintColor,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: frame.midX - textSize.width / 2,
                                            y: frame.midY - textSize.height / 2),
                                withAttributes: attrs)
    }
}
