import Foundation

nonisolated enum Config {
    private static let envVars: [String: String] = {
        func candidateEnvURLs() -> [URL] {
            var urls: [URL] = []
            urls.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".env"))
            urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env"))
            #if DEBUG
            // Resolve repository-root .env from this source file's compile-time path.
            let repoRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            urls.append(repoRoot.appendingPathComponent(".env"))
            #endif

            var seen: Set<String> = []
            return urls.filter { seen.insert($0.path).inserted }
        }

        var vars: [String: String] = [:]
        for url in candidateEnvURLs() {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                for line in contents.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                    let assignment = trimmed.hasPrefix("export ")
                        ? String(trimmed.dropFirst("export ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        : trimmed
                    let parts = assignment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    if parts.count == 2 {
                        let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let value = String(parts[1])
                        if let sanitized = sanitizeValue(value) {
                            vars[key] = sanitized
                        }
                    }
                }
                break
            }
        }
        return vars
    }()

    static var openAIKey: String {
        resolveValue(forKeys: ["OPENAI_API_KEY", "OPENAI_KEY"])
    }

    static var falKey: String {
        resolveValue(forKeys: ["FAL_KEY", "FAL_API_KEY"])
    }

    private static func resolveValue(forKeys keys: [String]) -> String {
        for key in keys {
            if let value = ProcessInfo.processInfo.environment[key], let sanitized = sanitizeValue(value) {
                return sanitized
            }
            if let value = envVars[key], let sanitized = sanitizeValue(value) {
                return sanitized
            }
        }

        return ""
    }

    private static func sanitizeValue(_ value: String) -> String? {
        var sanitized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")

        if sanitized.hasPrefix("\""), sanitized.hasSuffix("\""), sanitized.count >= 2 {
            sanitized.removeFirst()
            sanitized.removeLast()
        } else if sanitized.hasPrefix("'"), sanitized.hasSuffix("'"), sanitized.count >= 2 {
            sanitized.removeFirst()
            sanitized.removeLast()
        }

        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }
}
