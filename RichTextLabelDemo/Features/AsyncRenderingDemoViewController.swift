//
//  AsyncRenderingDemoViewController.swift
//  RichTextLabelDemo
//
//  Created by v on 9/29/26.
//
//  演示④：异步渲染 —— rendersAsynchronously 开关。
//  开关写进 DemoSettings，所以它作用到全部演示 label：本页立刻生效，其它页面（含之后新建的）跟着变。
//

import UIKit

final class AsyncRenderingDemoViewController: DemoPageViewController {

    private let toggle = UISwitch()
    private let settings = DemoSettings.shared

    init() {
        super.init(title: "④ 异步渲染",
                   intro: "开启后 TextDisplayLayer.draw(in:) 里录制的绘制命令由 CoreAnimation 延后执行，"
                        + "display() 更快返回；排版和状态读写仍在主线程，不引入数据竞争。"
                        + "画面与关闭时一致：正文逐位相同，彩色内容仅抗锯齿边缘有 LSB 级色差 —— "
                        + "收益在主线程耗时，不在外观，所以拨开关看不出差别。"
                        + "许可性语义，系统可以不采纳；逐帧变化的内容（动画）不适合开。"
                        + "试着开关之后拖动底部的字号步进器、点几个 token，两种模式下行为应当一致。")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 别的页面也可能改过这个开关（设置在页面间共享），回到本页时同步一下。
        toggle.isOn = settings.asyncRenderingEnabled
    }

    override func buildContent() {
        let switchCard = addCard(title: "开关（作用于全部演示 label）")

        let caption = UILabel()
        caption.text = "异步渲染"
        caption.font = .systemFont(ofSize: 14)
        caption.textColor = .secondaryLabel
        // 让标题吃掉剩余宽度，把开关推到行尾。
        caption.setContentHuggingPriority(.defaultLow, for: .horizontal)

        toggle.isOn = settings.asyncRenderingEnabled
        toggle.addTarget(self, action: #selector(asyncRenderingChanged(_:)), for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [caption, toggle])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        switchCard.addArrangedSubview(row)

        // 开关需要一个作用对象：这里放一张把三种 token 混在一起的 label，
        // 绘制量比纯文字大，来回切换 + 调字号更容易观察两种模式下行为一致。
        let card = addCard(title: "混合内容：emoji + 链接 + @提及 + 徽章")

        let label = makeDemoLabel()
        label.registry.register(DemoEmoji.tokenRule())
        label.registry.register(URLTokenRule())
        label.registry.register(MentionTokenRule())
        label.registry.register(BadgeTokenRule())
        label.text = "发布 :tada: 详情 https://example.com/build/42 找 @alice [vip] 用户优先体验 :rocket: [beta] 通道 [new]"
        card.addArrangedSubview(label)
    }

    @objc private func asyncRenderingChanged(_ sender: UISwitch) {
        settings.asyncRenderingEnabled = sender.isOn
        // 和字号步进器同理：作用到本页全部演示 label，方便来回切换对比。
        // 切换本身会触发重绘，两种模式下画面应当完全一致。
        applySettings()
    }
}
