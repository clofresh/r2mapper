import Foundation

/// What a button does. Either a keystroke (`key` + optional `modifiers`) or a `shell` command.
struct Action: Codable {
    var label: String?
    var key: String?
    var modifiers: [String]?
    var shell: String?

    var summary: String {
        if let label { return label }
        if let key { return ((modifiers ?? []) + [key]).joined(separator: "+") }
        if let shell { return "$ \(shell)" }
        return "nothing"
    }
}

/// `buttons` applies everywhere; `apps` overrides individual buttons per frontmost app bundle ID.
struct Config: Codable {
    var buttons: [String: Action]
    var apps: [String: [String: Action]]?

    func action(for button: RingButton, frontmostBundleID: String?) -> Action? {
        if let id = frontmostBundleID, let override = apps?[id]?[button.rawValue] { return override }
        return buttons[button.rawValue]
    }

    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("R2Mapper", isDirectory: true)
        return dir.appendingPathComponent("config.json")
    }()

    /// Slideshow defaults that work in Keynote, PowerPoint, Google Slides and most PDF viewers.
    static let presentationDefault = Config(
        buttons: [
            "right": Action(label: "Next slide", key: "right"),
            "down": Action(label: "Next slide", key: "right"),
            "left": Action(label: "Previous slide", key: "left"),
            "up": Action(label: "Previous slide", key: "left"),
            "ok": Action(label: "Start slideshow", key: "return", modifiers: ["cmd"]),
            "home": Action(label: "Black screen (toggle)", key: "b"),
        ],
        apps: [
            "com.apple.iWork.Keynote": [
                "ok": Action(label: "Play slideshow", key: "p", modifiers: ["cmd", "option"]),
            ],
        ]
    )

    static func load() -> (Config, String?) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            presentationDefault.save()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return (try JSONDecoder().decode(Config.self, from: data), nil)
        } catch {
            return (presentationDefault, "Couldn't read config, using defaults: \(error.localizedDescription)")
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(self).write(to: Config.fileURL)
    }
}
