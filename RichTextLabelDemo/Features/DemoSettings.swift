//
//  DemoSettings.swift
//  RichTextLabelDemo
//
//  Created by v on 9/29/26.
//
//  跨子页面共享的演示参数。
//  改成「列表 + 每个 feature 一个子页面」之后，同屏只有当前页的 label，
//  但字号和异步渲染开关的语义仍然是全局的：在任一页面调过，其它页面（包括之后新建的）都跟着变。
//

import UIKit

final class DemoSettings {
    static let shared = DemoSettings()

    /// 步进器的可调范围。
    static let fontSizeRange: ClosedRange<Double> = 13...24

    /// 演示 label 的正文字号。
    var fontSize: CGFloat = 17

    /// 演示④：异步渲染开关，新建 label 时套用。
    var asyncRenderingEnabled = false

    private init() {}
}
