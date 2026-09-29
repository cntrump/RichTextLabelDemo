//
//  EmojiDemoViewController.swift
//  RichTextLabelDemo
//
//  Created by v on 9/29/26.
//
//  演示①：自定义 emoji —— EmojiTokenRule + 异步 ImageDecoration（占位块 → 真图，只重绘不重排）。
//

import UIKit

final class EmojiDemoViewController: DemoPageViewController {

    init() {
        super.init(title: "① 自定义 emoji",
                   intro: ":name: 由 EmojiTokenRule 识别并替换成 U+FFFC attachment。loader 模拟 0.8s 网络延迟，"
                        + "期间显示灰色占位块；占位尺寸即最终尺寸，图片到位只重绘不重排。"
                        + ":wtf: 未注册，保留原文。")
    }

    override func buildContent() {
        let card = addCard(title: "异步加载：先看占位块，0.8s 后换真图")

        let label = makeDemoLabel()
        label.registry.register(DemoEmoji.tokenRule())
        label.text = "版本发布成功 :tada: 性能起飞 :rocket: 热门 :fire: 围观 :eyes: 未知表情 :wtf: 保持原样"
        card.addArrangedSubview(label)
    }
}
