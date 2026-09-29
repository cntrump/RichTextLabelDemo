//
//  TextTokenDemoViewController.swift
//  RichTextLabelDemo
//
//  Created by v on 9/29/26.
//
//  演示②：文字型 token —— URL / @提及 / #话题，保留文字形态、只叠加属性；
//  按钮演示「设置 text 之后」运行期注册规则 + reload() 热生效。
//

import UIKit

final class TextTokenDemoViewController: DemoPageViewController {

    /// 运行期注册 #话题 规则的目标 label。
    private weak var hashtagLabel: RichTextLabel?
    private var hashtagRuleEnabled = false

    init() {
        super.init(title: "② 文字型 token",
                   intro: "URL 用内置 URLTokenRule（NSDataDetector + .link 属性，点击直接打开）；"
                        + "@提及是自定义规则：保留文字形态、只叠加颜色和 tokenID。"
                        + "#TextKit2 此刻还是普通文字 —— 点下面按钮运行期注册规则并 reload()。")
    }

    override func buildContent() {
        let card = addCard(title: "链接、@提及、#话题")

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
}
