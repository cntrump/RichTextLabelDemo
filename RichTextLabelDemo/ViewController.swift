//
//  ViewController.swift
//  RichTextLabelDemo
//
//  Created by v on 9/28/26.
//
//  RichTextLabel 演示，覆盖三个扩展点：
//  ① 自定义 emoji —— EmojiTokenRule + 异步 ImageDecoration（占位块 → 真图，只重绘不重排）
//  ② 文字型 token —— URL / @提及 / #话题（保留文字、叠加属性；#话题 演示运行期注册规则 + reload()）
//  ③ 自绘徽章 —— 自定义 TextTokenRule + InlineDecoration，纯 CoreGraphics 绘制，不依赖图片资源
//  底部：字号步进器（font didSet → 重新编译，图标随字号缩放）+ 最近一次点击的 token 信息。
//

import UIKit

class ViewController: UIViewController {

    // MARK: - 状态

    private var currentFontSize: CGFloat = 17
    /// 参与字号调节的所有演示 label。
    private var demoLabels: [RichTextLabel] = []
    /// 演示②：运行期注册 #话题 规则的目标 label。
    private weak var hashtagLabel: RichTextLabel?
    private var hashtagRuleEnabled = false

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let statusLabel = UILabel()
    private let fontSizeLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "RichTextLabel Demo"

        setupChrome()
        addEmojiDemo()
        addTextTokenDemo()
        addBadgeDemo()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Auto Layout 下多行自适应高度需要告知可用宽度，语义同 UILabel.preferredMaxLayoutWidth。
        for label in demoLabels where abs(label.preferredMaxLayoutWidth - contentStack.bounds.width) > 0.01 {
            label.preferredMaxLayoutWidth = contentStack.bounds.width
        }
    }

    // MARK: - 骨架

    private func setupChrome() {
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 28
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        // 底部状态栏：字号调节 + 最近一次点击的 token。
        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.text = "点击任意高亮 token 试试"

        fontSizeLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        fontSizeLabel.text = "字号 17 pt"

        let stepper = UIStepper()
        stepper.value = Double(currentFontSize)
        stepper.minimumValue = 13
        stepper.maximumValue = 24
        stepper.addTarget(self, action: #selector(fontSizeChanged(_:)), for: .valueChanged)

        let fontRow = UIStackView(arrangedSubviews: [fontSizeLabel, stepper])
        fontRow.spacing = 8

        let bottomBar = UIStackView(arrangedSubviews: [fontRow, statusLabel])
        bottomBar.axis = .vertical
        bottomBar.spacing = 6
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: guide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -12),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),

            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -10),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            bottomBar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            bottomBar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            bottomBar.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8),
        ])
    }

    /// 建一张卡片（标题 + 说明），返回卡片 stack，调用方继续往里追加 label / 按钮。
    @discardableResult
    private func addCard(title: String, detail: String) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.numberOfLines = 0

        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0

        let card = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        card.axis = .vertical
        card.spacing = 8
        contentStack.addArrangedSubview(card)
        return card
    }

    /// 统一的演示 label 工厂：卡片底色、内边距、点击回调都在这配好。
    private func makeDemoLabel() -> RichTextLabel {
        let label = RichTextLabel()
        label.backgroundColor = .secondarySystemBackground
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.textInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        label.font = .systemFont(ofSize: currentFontSize)
        label.numberOfLines = 0
        label.onTokenTap = { [weak self] token in
            self?.handleTokenTap(token)
        }
        demoLabels.append(label)
        return label
    }

    // MARK: - 演示① 自定义 emoji

    private func addEmojiDemo() {
        let card = addCard(
            title: "① 自定义 emoji（异步加载 + 占位块）",
            detail: ":name: 由 EmojiTokenRule 识别并替换成 U+FFFC attachment。loader 模拟 0.8s 网络延迟，"
                  + "期间显示灰色占位块；占位尺寸即最终尺寸，图片到位只重绘不重排。:wtf: 未注册，保留原文。")

        let label = makeDemoLabel()
        label.registry.register(EmojiTokenRule(
            isKnownName: { DemoEmoji.unicode[$0] != nil },
            loader: { name, completion in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                    completion(DemoEmoji.unicode[name].map { DemoEmoji.render($0) })
                }
            }))
        label.text = "版本发布成功 :tada: 性能起飞 :rocket: 热门 :fire: 围观 :eyes: 未知表情 :wtf: 保持原样"
        card.addArrangedSubview(label)
    }

    // MARK: - 演示② URL / @提及 / #话题

    private func addTextTokenDemo() {
        let card = addCard(
            title: "② 文字型 token：链接、@提及、#话题",
            detail: "URL 用内置 URLTokenRule（NSDataDetector + .link 属性）；@提及是自定义规则：保留文字形态、"
                  + "只叠加颜色和 tokenID。#TextKit2 此刻还是普通文字 —— 点下面按钮运行期注册规则并 reload()。")

        let label = makeDemoLabel()
        label.registry.register(URLTokenRule())
        label.registry.register(MentionTokenRule())
        label.text = "构建日志 https://example.com/build/42 有问题找 @alice 抄送 @bob #TextKit2"
        card.addArrangedSubview(label)
        hashtagLabel = label

        let button = UIButton(type: .system)
        button.setTitle("注册 #话题 规则并 reload()", for: .normal)
        button.contentHorizontalAlignment = .left
        button.addTarget(self, action: #selector(enableHashtagRule(_:)), for: .touchUpInside)
        card.addArrangedSubview(button)
    }

    @objc private func enableHashtagRule(_ sender: UIButton) {
        guard !hashtagRuleEnabled, let label = hashtagLabel else { return }
        hashtagRuleEnabled = true
        // 设置 text 之后才注册新规则：原始纯文本还在，reload() 重新编译即可生效。
        label.registry.register(HashtagTokenRule())
        label.reload()
        sender.setTitle("#话题 规则已注册，reload() 生效", for: .normal)
        sender.isEnabled = false
    }

    // MARK: - 演示③ 自绘徽章

    private func addBadgeDemo() {
        let card = addCard(
            title: "③ 自绘徽章（InlineDecoration 扩展点）",
            detail: "[name] 由自定义 BadgeTokenRule 识别，BadgeDecoration 在 draw(in:frame:state:) 里直接画"
                  + "胶囊和文字 —— 不走 NSTextAttachment.image，任何 CoreGraphics 内容都能内联，点击同样有回调。")

        let label = makeDemoLabel()
        label.registry.register(BadgeTokenRule())
        label.text = "恭喜 [vip] 用户：[beta] 反馈通道已开放，[new] 徽章全部由代码绘制"
        card.addArrangedSubview(label)
    }

    // MARK: - 交互

    private func handleTokenTap(_ token: TokenTap) {
        statusLabel.text = "点击 [\(token.identifier)] payload: \(token.payload) range: \(NSStringFromRange(token.range))"
        // 链接型 token：真实场景通常直接打开。
        if token.identifier == "url", let url = URL(string: token.payload) {
            UIApplication.shared.open(url)
        }
    }

    @objc private func fontSizeChanged(_ sender: UIStepper) {
        currentFontSize = CGFloat(sender.value)
        fontSizeLabel.text = String(format: "字号 %.0f pt", currentFontSize)
        for label in demoLabels {
            // font didSet → 用原始纯文本重新编译；emoji / 徽章尺寸随字号缩放。
            label.font = .systemFont(ofSize: currentFontSize)
        }
    }
}

// MARK: - 演示用 emoji 图集

/// 没有图片资源也能演示：把系统 unicode emoji 现渲染成图，充当「自定义表情图集」。
/// 真实项目里换成 `EmojiTokenRule(prefix:)` 从 asset catalog 加载即可。
private enum DemoEmoji {
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
}

// MARK: - 演示用 token 规则

/// @提及：文字型 token，只叠属性，不产生 attachment。
private final class MentionTokenRule: TextTokenRule {
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
private final class HashtagTokenRule: TextTokenRule {
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
private final class BadgeTokenRule: TextTokenRule {
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
private final class BadgeDecoration: InlineDecoration {
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
