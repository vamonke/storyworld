import Foundation
import UIKit

actor VideoGenerationClient {
    private let falKey: String

    init(falKey: String = Config.falKey) {
        self.falKey = falKey
    }

    func generateVideo(frames: [UIImage], scenePrompt: String) async throws -> URL {
        // Use first frame as the key image for video generation
        guard let firstFrame = frames.first,
              let imageData = firstFrame.jpegData(compressionQuality: 0.8) else {
            throw VideoError.noFrames
        }

        let base64Image = imageData.base64EncodedString()
        let dataURI = "data:image/jpeg;base64,\(base64Image)"

        let payload: [String: Any] = [
            "prompt": scenePrompt,
            "image_url": dataURI
        ]

        let url = URL(string: "https://queue.fal.run/fal-ai/kling-video/v1.5/pro/image-to-video")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Key \(falKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VideoError.networkError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VideoError.invalidResponse
        }

        // Direct result
        if httpResponse.statusCode == 200, let videoURL = extractVideoURL(from: json) {
            return try await downloadVideo(from: videoURL)
        }

        // Queued - poll
        guard let requestId = json["request_id"] as? String else {
            throw VideoError.invalidResponse
        }

        return try await pollForVideo(requestId: requestId)
    }

    private func pollForVideo(requestId: String) async throws -> URL {
        let endpoint = "fal-ai/kling-video/v1.5/pro/image-to-video"

        for _ in 0..<180 {
            try await Task.sleep(for: .seconds(3))

            let statusURL = URL(string: "https://queue.fal.run/\(endpoint)/requests/\(requestId)/status")!
            var request = URLRequest(url: statusURL)
            request.setValue("Key \(falKey)", forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else { continue }

            if status == "COMPLETED" {
                let resultURL = URL(string: "https://queue.fal.run/\(endpoint)/requests/\(requestId)")!
                var resultRequest = URLRequest(url: resultURL)
                resultRequest.setValue("Key \(falKey)", forHTTPHeaderField: "Authorization")

                let (resultData, _) = try await URLSession.shared.data(for: resultRequest)
                guard let result = try JSONSerialization.jsonObject(with: resultData) as? [String: Any],
                      let videoURL = extractVideoURL(from: result) else {
                    throw VideoError.invalidResponse
                }
                return try await downloadVideo(from: videoURL)
            } else if status == "FAILED" {
                throw VideoError.generationFailed
            }
        }

        throw VideoError.timeout
    }

    private func extractVideoURL(from json: [String: Any]) -> String? {
        if let video = json["video"] as? [String: Any], let url = video["url"] as? String {
            return url
        }
        return nil
    }

    private func downloadVideo(from urlString: String) async throws -> URL {
        guard let url = URL(string: urlString) else { throw VideoError.invalidResponse }
        let (data, _) = try await URLSession.shared.data(from: url)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        try data.write(to: fileURL)
        return fileURL
    }
}

enum VideoError: LocalizedError {
    case noFrames
    case networkError
    case invalidResponse
    case generationFailed
    case timeout

    var errorDescription: String? {
        switch self {
        case .noFrames: return "No frames to generate video from"
        case .networkError: return "Network error"
        case .invalidResponse: return "Invalid response"
        case .generationFailed: return "Video generation failed"
        case .timeout: return "Video generation timed out"
        }
    }
}
