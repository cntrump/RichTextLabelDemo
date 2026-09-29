//
//  DemoPageViewController.swift
//  RichTextLabelDemo
//
//  Created by v on 9/29/26.
//
//  每个 feature 子页面的公共骨架：滚动容器 + 卡片工厂 + 底部（字号步进器 / 最近点击的 token）。
//  子类只需要重写 buildContent()，往里追加卡片、label、控件。
//

import UIKit

class DemoPageViewController: UIViewController {

    /// 页面顶部说明卡片的文字。
    private let intro: String

    private let settings = DemoSettings.shared
    /// 参与字号调节、异步渲染切换的所有演示 label。
    private var demoLabels: [RichTextLabel] = []

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let statusLabel = UILabel()
    private let fontSizeLabel = UILabel()
    private let stepper = UIStepper()

    init(title: String, intro: String) {
        self.intro = intro
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        setupChrome()
        addCard(detail: intro)
        buildContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 设置是跨页面共享的：在别的页面调过字号 / 开关之后回到这里，label 和控制台都要跟上。
        applySettings()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Auto Layout 下多行自适应高度需要告知可用宽度，语义同 UILabel.preferredMaxLayoutWidth。
        for label in demoLabels where abs(label.preferredMaxLayoutWidth - contentStack.bounds.width) > 0.01 {
            label.preferredMaxLayoutWidth = contentStack.bounds.width
        }
    }

    /// 子类在这里往页面追加卡片 / label / 按钮，基类已经把说明卡片放好了。
    func buildContent() {}

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

        stepper.minimumValue = DemoSettings.fontSizeRange.lowerBound
        stepper.maximumValue = DemoSettings.fontSizeRange.upperBound
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

    /// 建一张卡片（可选标题 + 说明），返回卡片 stack，调用方继续往里追加 label / 按钮。
    @discardableResult
    func addCard(title: String? = nil, detail: String? = nil) -> UIStackView {
        var arrangedSubviews: [UIView] = []

        if let title {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            titleLabel.numberOfLines = 0
            arrangedSubviews.append(titleLabel)
        }

        if let detail {
            let detailLabel = UILabel()
            detailLabel.text = detail
            detailLabel.font = .systemFont(ofSize: 12)
            detailLabel.textColor = .secondaryLabel
            detailLabel.numberOfLines = 0
            arrangedSubviews.append(detailLabel)
        }

        let card = UIStackView(arrangedSubviews: arrangedSubviews)
        card.axis = .vertical
        card.spacing = 8
        contentStack.addArrangedSubview(card)
        return card
    }

    /// 统一的演示 label 工厂：卡片底色、内边距、点击回调都在这配好。
    func makeDemoLabel() -> RichTextLabel {
        let label = RichTextLabel()
        label.backgroundColor = .secondarySystemBackground
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.textInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        label.font = .systemFont(ofSize: settings.fontSize)
        label.rendersAsynchronously = settings.asyncRenderingEnabled
        label.numberOfLines = 0
        label.onTokenTap = { [weak self] token in
            self?.handleTokenTap(token)
        }
        demoLabels.append(label)
        return label
    }

    /// 把共享设置套到当前页的全部演示 label 和底部控件上。
    func applySettings() {
        stepper.value = Double(settings.fontSize)
        fontSizeLabel.text = String(format: "字号 %.0f pt", settings.fontSize)
        for label in demoLabels {
            // font didSet → 用原始纯文本重新编译；emoji / 徽章尺寸随字号缩放。
            label.font = .systemFont(ofSize: settings.fontSize)
            label.rendersAsynchronously = settings.asyncRenderingEnabled
        }
    }

    // MARK: - 交互

    func handleTokenTap(_ token: TokenTap) {
        statusLabel.text = "点击 [\(token.identifier)] payload: \(token.payload) range: \(NSStringFromRange(token.range))"
        // 链接型 token：真实场景通常直接打开。
        if token.identifier == "url", let url = URL(string: token.payload) {
            UIApplication.shared.open(url)
        }
    }

    @objc private func fontSizeChanged(_ sender: UIStepper) {
        settings.fontSize = CGFloat(sender.value)
        applySettings()
    }
}
