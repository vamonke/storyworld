import Foundation

actor OpenAIClient {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"

    init(apiKey: String = Config.openAIKey) {
        self.apiKey = apiKey
    }

    func transcribe(audioData: Data) async throws -> String {
        let url = URL(string: "\(baseURL)/audio/transcriptions")!
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // Model field
        body.appendMultipart(boundary: boundary, name: "model", value: "gpt-4o-mini-transcribe")
        // Audio file
        body.appendMultipart(boundary: boundary, name: "file", filename: "audio.wav", mimeType: "audio/wav", data: audioData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OpenAIError.transcriptionFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw OpenAIError.invalidResponse
        }

        return text
    }

    func parseIntent(text: String) async throws -> VoiceDirectorAction {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        You are a film director's assistant. Parse the user's voice command into one of these actions.
        Respond with ONLY a JSON object (no markdown, no explanation):
        - {"action": "capture"} — user wants to capture/take the current shot
        - {"action": "expression", "value": "<expression>"} — change character's facial expression
        - {"action": "pose", "value": "<pose>"} — change character's pose
        - {"action": "outfit", "value": "<outfit>"} — change character's outfit
        - {"action": "framing", "value": "<wide|closeUp|overShoulder>"} — suggest camera framing
        - {"action": "generate", "value": "<scene description>"} — generate a video with the description
        - {"action": "unknown", "value": "<original text>"} — if you can't parse the command
        """

        let payload: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.1
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OpenAIError.intentParsingFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let actionData = content.data(using: .utf8),
              let actionJSON = try JSONSerialization.jsonObject(with: actionData) as? [String: String],
              let action = actionJSON["action"] else {
            throw OpenAIError.invalidResponse
        }

        let value = actionJSON["value"] ?? ""

        switch action {
        case "capture": return .captureShot
        case "expression": return .changeExpression(value)
        case "pose": return .changePose(value)
        case "outfit": return .changeOutfit(value)
        case "framing":
            switch value {
            case "closeUp": return .suggestFraming(.closeUp)
            case "overShoulder": return .suggestFraming(.overShoulder)
            default: return .suggestFraming(.wide)
            }
        case "generate": return .generate(scenePrompt: value)
        default: return .unknown(value)
        }
    }
}

enum OpenAIError: LocalizedError {
    case transcriptionFailed
    case intentParsingFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .transcriptionFailed: return "Failed to transcribe audio"
        case .intentParsingFailed: return "Failed to parse intent"
        case .invalidResponse: return "Invalid response from OpenAI"
        }
    }
}

extension Data {
    nonisolated mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    nonisolated mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
