//
//  BadgeDemoViewController.swift
//  RichTextLabelDemo
//
//  Created by v on 9/29/26.
//
//  演示③：自绘徽章 —— 自定义 TextTokenRule + InlineDecoration，纯 CoreGraphics 绘制，不依赖图片资源。
//

import UIKit

final class BadgeDemoViewController: DemoPageViewController {

    init() {
        super.init(title: "③ 自绘徽章",
                   intro: "[name] 由自定义 BadgeTokenRule 识别，BadgeDecoration 在 draw(in:frame:state:) 里直接画"
                        + "胶囊和文字 —— 不走 NSTextAttachment.image，任何 CoreGraphics 内容都能内联，点击同样有回调。"
                        + "未登记的名字（如 [todo]）保留原文。")
    }

    override func buildContent() {
        let card = addCard(title: "胶囊 + 描边 + 文字，全部代码绘制")

        let label = makeDemoLabel()
        label.registry.register(BadgeTokenRule())
        label.text = "恭喜 [vip] 用户：[beta] 反馈通道已开放，[new] 徽章全部由代码绘制，[todo] 未登记保留原文"
        card.addArrangedSubview(label)
    }
}
