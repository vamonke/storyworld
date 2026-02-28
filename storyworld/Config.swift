import Foundation

nonisolated enum Config {
    private static let envVars: [String: String] = {
        var vars: [String: String] = [:]
        // Look for .env in the app bundle's parent or common locations
        let candidates = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".env"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("dev/storyworld/.env")
        ]
        for url in candidates {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                for line in contents.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        vars[String(parts[0])] = String(parts[1])
                    }
                }
                break
            }
        }
        return vars
    }()

    static var openAIKey: String {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? envVars["OPENAI_API_KEY"] ?? ""
    }

    static var falKey: String {
        ProcessInfo.processInfo.environment["FAL_KEY"] ?? envVars["FAL_KEY"] ?? ""
    }
}
