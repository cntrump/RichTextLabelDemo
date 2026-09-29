//
//  DemoFeature.swift
//  RichTextLabelDemo
//
//  Created by v on 9/29/26.
//
//  列表数据源：一行 = RichTextKit 的一个扩展点，点开进入对应的子页面。
//  新增 feature 只要在这里追加一项，列表和导航自动跟上。
//

import UIKit

struct DemoFeature {
    /// 列表主标题。
    let title: String
    /// 列表副标题：一句话说明这个 feature 演示什么。
    let subtitle: String
    /// 子页面工厂，点击时调用。
    let makeViewController: () -> UIViewController
}

extension DemoFeature {
    static let all: [DemoFeature] = [
        DemoFeature(title: "① 自定义 emoji",
                    subtitle: "EmojiTokenRule + 异步 ImageDecoration：占位块 → 真图，只重绘不重排",
                    makeViewController: { EmojiDemoViewController() }),
        DemoFeature(title: "② 文字型 token",
                    subtitle: "URL / @提及 / #话题：保留文字、叠加属性；#话题 演示运行期注册规则 + reload()",
                    makeViewController: { TextTokenDemoViewController() }),
        DemoFeature(title: "③ 自绘徽章",
                    subtitle: "自定义 TextTokenRule + InlineDecoration，纯 CoreGraphics 绘制，不依赖图片资源",
                    makeViewController: { BadgeDemoViewController() }),
        DemoFeature(title: "④ 异步渲染",
                    subtitle: "rendersAsynchronously 开关：画面一致，收益在主线程耗时",
                    makeViewController: { AsyncRenderingDemoViewController() }),
    ]
}
