import Foundation

public struct NextStep: Equatable, Decodable {
    public var project: String
    public var round: Int
    public var action: String
    public var lineZh: String
    public var lineEn: String
    public var file: String
    public var opener: String

    public init(
        project: String,
        round: Int,
        action: String,
        lineZh: String,
        lineEn: String,
        file: String,
        opener: String
    ) {
        self.project = project
        self.round = round
        self.action = action
        self.lineZh = lineZh
        self.lineEn = lineEn
        self.file = file
        self.opener = opener
    }

    enum CodingKeys: String, CodingKey {
        case project, round, action, file, opener
        case lineZh = "line_zh"
        case lineEn = "line_en"
    }

    public func line(chinese: Bool) -> String {
        let chosen = chinese ? lineZh : lineEn
        if !chosen.isEmpty { return chosen }
        return chinese ? lineEn : lineZh
    }
}

public enum NextStepFallback {
    public static func make(
        project: ProjectStatus?,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> NextStep {
        guard let project else {
            return NextStep(
                project: "",
                round: 0,
                action: "add",
                lineZh: "点「添加项目」，选你的代码文件夹。",
                lineEn: "Choose Add Project and pick your code folder.",
                file: "",
                opener: ""
            )
        }
        let label = String(format: "R%03d", project.round)
        let alias = (project.outboxDir as NSString).appendingPathComponent("to_chatgpt_\(label).md")
        let plain = (project.outboxDir as NSString).appendingPathComponent("to_chatgpt.md")
        let file: String
        if fileExists(alias) {
            file = alias
        } else if fileExists(plain) {
            file = plain
        } else if !project.packFile.isEmpty && fileExists(project.packFile) {
            file = project.packFile
        } else {
            file = ""
        }
        let action: String
        let zh: String
        let en: String
        if project.inboxState == "new" {
            action = "review"
            zh = "回复到了。打开收回夹，让助手处理这一轮。"
            en = "The reply is in. Open the inbox and let your agent handle this round."
        } else if !project.error.isEmpty {
            action = "fix"
            zh = "先处理这个错误：\(project.error)"
            en = "Deal with this first: \(project.error)"
        } else if !file.isEmpty && project.packState == "presented" {
            action = "wait"
            zh = "如果还没发，把选中的文件拖进 ChatGPT，自己点发送。发完把回复下载下来。"
            en = "If you have not sent it, drag the selected file into ChatGPT and press send yourself. Then download the reply."
        } else if !file.isEmpty {
            action = "send"
            zh = "点右边按钮，然后把选中的文件拖进 ChatGPT，自己点发送。"
            en = "Press the button, then drag the selected file into ChatGPT and press send yourself."
        } else {
            action = "pack"
            zh = "这一轮还没有文件。让助手运行 chatbar pack。"
            en = "This round has no file yet. Ask your agent to run chatbar pack."
        }
        return NextStep(
            project: project.name,
            round: project.round,
            action: action,
            lineZh: zh,
            lineEn: en,
            file: file,
            opener: ""
        )
    }
}
