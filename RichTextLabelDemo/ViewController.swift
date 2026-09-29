//
//  ViewController.swift
//  RichTextLabelDemo
//
//  Created by v on 9/28/26.
//
//  演示 App 入口：列表列出 RichTextKit 的全部扩展点，每个 feature 一个独立子页面。
//  ① 自定义 emoji ② 文字型 token ③ 自绘徽章 ④ 异步渲染
//  列表数据源见 Features/DemoFeature.swift，子页面公共骨架见 Features/DemoPageViewController.swift。
//

import UIKit

class ViewController: UIViewController {

    private static let cellID = "FeatureCell"

    private let features = DemoFeature.all
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "RichTextLabel Demo"

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        // 顶到 view 四边，让 insetGrouped 的分组头和导航栏之间的间距由系统自动 inset 处理。
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension ViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        features.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellID, for: indexPath)
        let feature = features[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = feature.title
        content.secondaryText = feature.subtitle
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(features[indexPath.row].makeViewController(), animated: true)
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "每个 feature 一个子页面；字号与异步渲染设置在页面之间共享。"
    }
}
