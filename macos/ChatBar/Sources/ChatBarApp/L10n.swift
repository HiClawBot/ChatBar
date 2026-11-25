import Foundation

enum L10n {
    static var chinese: Bool {
        let preferred = Locale.preferredLanguages.first ?? "zh-Hans"
        return !preferred.hasPrefix("en")
    }

    static func text(_ key: String) -> String {
        if let value = localized(key), value != key, !value.isEmpty {
            return value
        }
        return fallback[key] ?? key
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: args)
    }

    /// Loads every shipped string and returns 0. Does not touch the Swift package resource bundle.
    static func selfTest() -> Int32 {
        var missing: [String] = []
        for key in fallback.keys.sorted() {
            let value = text(key)
            if value.isEmpty {
                missing.append(key)
            }
        }
        if !missing.isEmpty {
            fputs("l10n missing: \(missing.joined(separator: ", "))\n", stderr)
            return 1
        }
        print("l10n ok \(fallback.count)")
        return 0
    }

    private static func localized(_ key: String) -> String? {
        let code = chinese ? "zh-Hans" : "en"
        let roots = [Bundle.main]
        for root in roots {
            if let path = root.path(forResource: code, ofType: "lproj"),
               let table = Bundle(path: path) {
                let value = table.localizedString(forKey: key, value: sentinel, table: "Localizable")
                if value != sentinel && value != key {
                    return value
                }
            }
            let mainValue = root.localizedString(forKey: key, value: sentinel, table: "Localizable")
            if mainValue != sentinel && mainValue != key {
                return mainValue
            }
        }
        return nil
    }

    private static let sentinel = "\u{0}"

    private static let fallback: [String: String] = [
        "card.copy": "复制第 %d 轮（开场白+文件）",
        "card.waiting": "等 GPT 回复中…",
        "card.reply": "回复已收到 · 助手处理中",
        "card.idle": "这一轮还没有包",
        "card.failed": "出错了",
        "cli.timeout": "读取超时",
        "cli.readFailed": "读取失败",
        "cli.commandFailed": "操作失败",
        "card.empty": "添加项目",
        "auto.title": "自动收发：%@",
        "auto.on": "开",
        "auto.off": "关",
        "auto.project": "本项目",
        "pick.title": "选择项目",
        "pick.nomatch": "无法判断是哪个项目",
        "pick.ambiguous": "匹配到多个项目",
        "pick.round": "轮次对不上",
        "pick.choose": "归入…",
        "opener.title": "给 GPT 的话",
        "opener.hide": "收起",
        "opener.show": "展开",
        "opener.reset": "恢复助手版本",
        "folder.out": "发出",
        "folder.in": "收回",
        "folder.root": "总目录",
        "notify.ready": "第 %d 轮已就绪，去 %@ 按 Cmd+V 发送",
        "notify.pending": "有下载无法自动归入项目，请在卡片里选择。",
        "notify.reply": "已收到「%@」的回复",
        "welcome.title": "ChatBar",
        "welcome.body": "ChatBar 只放在菜单栏。复制、粘贴、发送、下载都由你自己完成。它不会去点任何聊天软件。",
        "welcome.ok": "好",
        "menu.safety": "发送要你自己做。ChatBar 不操作聊天软件。",
        "menu.settings": "设置…",
        "bar.title": "吧台",
        "bar.room": "包厢",
        "bar.tip": "小费罐",
        "bar.tipMinutes": "省下 %@ 分钟",
        "bar.tipCost": "少花 %@",
        "bar.scene": "场景",
        "bar.sceneLater": "机器人动画以后再做。现在按记录列出每一步。",
        "settings.leftClick": "左键打开",
        "settings.leftBar": "吧台窗口",
        "settings.leftCard": "小卡片",
        "settings.tipMinutes": "每步分钟",
        "settings.tipCost": "每轮费用",
        "settings.save": "存储",
        "next.button": "复制开场白并选中文件",
        "menu.back": "上一步",
        "menu.more": "更多",
        "menu.add": "添加项目…",
        "add.choose": "添加",
        "add.message": "选代码文件夹。项目名用文件夹的名字。"
    ]
}
