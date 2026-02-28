import FalClient
import Foundation

actor FalService {
    private let client: Client
    private let apiKey: String
    private let nanoBanana2EditEndpoint = "fal-ai/nano-banana-2/edit"
    private let nanoBananaEditEndpoint = "fal-ai/nano-banana/edit"
    private let seedream45EditEndpoint = "fal-ai/bytedance/seedream/v4.5/edit"
    private let seedream4EditEndpoint = "fal-ai/bytedance/seedream/v4/edit"
    private let flux2ProEditEndpoint = "fal-ai/flux-2-pro/edit"
    private let seedanceFastImageToVideoEndpoint = "fal-ai/bytedance/seedance/v1/pro/fast/image-to-video"

    init(apiKey: String = Config.falKey) {
        self.apiKey = apiKey
        self.client = FalClient.withCredentials(.keyPair(apiKey))
    }

    func stylizeImage(imageData: Data) async throws -> Data {
        let dataURI = imageData.dataURI()

        let result = try await client.subscribe(to: "fal-ai/flux/dev/image-to-image", input: [
            "prompt": "Pixar 3D animated character style, colorful, expressive, high quality rendering, cinematic lighting, Disney Pixar aesthetic",
            "image_url": .string(dataURI),
            "strength": 0.65,
            "num_inference_steps": 28,
            "guidance_scale": 7.5
        ])

        guard let imageURL = result["images"][0]["url"].stringValue else {
            throw FalServiceError.invalidResponse
        }

        return try await downloadImage(from: imageURL)
    }

    func generate3DModel(imageData: Data) async throws -> URL {
        let dataURI = imageData.dataURI()

        let result = try await client.subscribe(to: "fal-ai/trellis", input: [
            "image_url": .string(dataURI)
        ])

        guard let modelURLString = result["model_mesh"]["url"].stringValue,
              let modelURL = URL(string: modelURLString) else {
            throw FalServiceError.invalidResponse
        }

        return try await downloadModel(from: modelURL)
    }

    func cinematicShot(imageData: Data, prompt: String) async throws -> Data {
        guard !apiKey.isEmpty else {
            throw FalServiceError.missingAPIKey
        }

        let dataURI = imageData.dataURI()
        let input: Payload = [
            "prompt": .string(prompt),
            "image_urls": [.string(dataURI)],
            "output_format": .string("jpeg")
        ]

        do {
            let result = try await client.subscribe(to: nanoBanana2EditEndpoint, input: input)

            guard let imageURL = result["images"][0]["url"].stringValue else {
                throw FalServiceError.invalidResponse
            }

            return try await downloadImage(from: imageURL)
        } catch let falError as FalServiceError {
            throw falError
        } catch {
            let probe = await probeQueueFailureDetails(endpoint: nanoBanana2EditEndpoint, input: input)
            throw FalServiceError.generationFailed(reason: appendProbe(debugReason(for: error), probe: probe))
        }
    }

    func cinematicShotNanoBanana(imageData: Data, prompt: String) async throws -> Data {
        guard !apiKey.isEmpty else {
            throw FalServiceError.missingAPIKey
        }

        let dataURI = imageData.dataURI()
        let input: Payload = [
            "prompt": .string(prompt),
            "image_urls": [.string(dataURI)],
            "num_images": 1,
            "aspect_ratio": .string("auto"),
            "output_format": .string("png")
        ]

        do {
            let result = try await client.subscribe(to: nanoBananaEditEndpoint, input: input)

            guard let imageURL = result["images"][0]["url"].stringValue else {
                throw FalServiceError.invalidResponse
            }

            return try await downloadImage(from: imageURL)
        } catch let falError as FalServiceError {
            throw falError
        } catch {
            let probe = await probeQueueFailureDetails(endpoint: nanoBananaEditEndpoint, input: input)
            throw FalServiceError.generationFailed(reason: appendProbe(debugReason(for: error), probe: probe))
        }
    }

    func cinematicShotSeedream45(imageData: Data, prompt: String) async throws -> Data {
        guard !apiKey.isEmpty else {
            throw FalServiceError.missingAPIKey
        }

        let dataURI = imageData.dataURI()
        let input: Payload = .dict([
            "prompt": .string(prompt),
            "image_urls": .array([.string(dataURI)]),
            "image_size": .string("auto_2K"),
            "num_images": .int(1),
            "max_images": .int(1),
            "enable_safety_checker": .bool(true)
        ])

        do {
            let result = try await client.subscribe(to: seedream45EditEndpoint, input: input)

            guard let imageURL = result["images"][0]["url"].stringValue else {
                throw FalServiceError.invalidResponse
            }

            return try await downloadImage(from: imageURL)
        } catch {
            let primaryReason = debugReason(for: error)
            // Some keys/accounts may not have Seedream 4.5 access; try v4 with the same payload.
            do {
                let fallbackResult = try await client.subscribe(to: seedream4EditEndpoint, input: input)
                guard let imageURL = fallbackResult["images"][0]["url"].stringValue else {
                    throw FalServiceError.invalidResponse
                }
                return try await downloadImage(from: imageURL)
            } catch {
                let fallbackReason = debugReason(for: error)
                async let probe45 = probeQueueFailureDetails(endpoint: seedream45EditEndpoint, input: input)
                async let probe4 = probeQueueFailureDetails(endpoint: seedream4EditEndpoint, input: input)
                let probe45Result = await probe45
                let probe4Result = await probe4
                let combinedProbe = [
                    probe45Result.map { "probe-v4.5: \($0)" },
                    probe4Result.map { "probe-v4: \($0)" }
                ]
                .compactMap { $0 }
                .joined(separator: " | ")
                throw FalServiceError.generationFailed(
                    reason: appendProbe(
                        "seedream-v4.5 failed: \(primaryReason) | seedream-v4 fallback failed: \(fallbackReason)",
                        probe: combinedProbe
                    )
                )
            }
        }
    }

    func cinematicShotFlux2Pro(imageData: Data, prompt: String) async throws -> Data {
        guard !apiKey.isEmpty else {
            throw FalServiceError.missingAPIKey
        }

        let dataURI = imageData.dataURI()
        let input: Payload = .dict([
            "prompt": .string(prompt),
            "image_urls": .array([.string(dataURI)]),
            "image_size": .string("auto"),
            "safety_tolerance": .string("5"),
            "enable_safety_checker": .bool(false),
            "output_format": .string("jpeg")
        ])

        do {
            let result = try await client.subscribe(to: flux2ProEditEndpoint, input: input)

            guard let imageURL = result["images"][0]["url"].stringValue else {
                throw FalServiceError.invalidResponse
            }

            return try await downloadImage(from: imageURL)
        } catch let falError as FalServiceError {
            throw falError
        } catch {
            let probe = await probeQueueFailureDetails(endpoint: flux2ProEditEndpoint, input: input)
            throw FalServiceError.generationFailed(reason: appendProbe(debugReason(for: error), probe: probe))
        }
    }

    func animateImageSeedanceFast(imageData: Data, prompt: String) async throws -> URL {
        guard !apiKey.isEmpty else {
            throw FalServiceError.missingAPIKey
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw FalServiceError.generationFailed(reason: "Prompt is required")
        }

        let dataURI = imageData.dataURI()
        let input: Payload = .dict([
            "prompt": .string(trimmedPrompt),
            "image_url": .string(dataURI),
            "aspect_ratio": .string("auto"),
            "resolution": .string("1080p"),
            "duration": .string("5"),
            "camera_fixed": .bool(false),
            "enable_safety_checker": .bool(true)
        ])

        do {
            let result = try await client.subscribe(to: seedanceFastImageToVideoEndpoint, input: input)
            guard let videoURL = result["video"]["url"].stringValue else {
                throw FalServiceError.invalidResponse
            }
            return try await downloadVideo(from: videoURL)
        } catch let falError as FalServiceError {
            throw falError
        } catch {
            let probe = await probeQueueFailureDetails(endpoint: seedanceFastImageToVideoEndpoint, input: input)
            throw FalServiceError.generationFailed(reason: appendProbe(debugReason(for: error), probe: probe))
        }
    }

    private func downloadImage(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw FalServiceError.invalidResponse }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw FalServiceError.generationFailed(reason: "Failed to download generated image (HTTP \(http.statusCode))")
        }
        guard !data.isEmpty else {
            throw FalServiceError.invalidResponse
        }
        return data
    }

    private func downloadModel(from url: URL) async throws -> URL {
        let (data, _) = try await URLSession.shared.data(from: url)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("usdz")
        try data.write(to: fileURL)
        return fileURL
    }

    private func downloadVideo(from urlString: String) async throws -> URL {
        guard let url = URL(string: urlString) else { throw FalServiceError.invalidResponse }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw FalServiceError.generationFailed(reason: "Failed to download generated video (HTTP \(http.statusCode))")
        }
        guard !data.isEmpty else {
            throw FalServiceError.invalidResponse
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        try data.write(to: fileURL)
        return fileURL
    }

    private func debugReason(for error: Error) -> String {
        let nsError = error as NSError
        var parts: [String] = []
        let description = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty {
            parts.append(description)
        }
        if let failureReason = nsError.localizedFailureReason,
           !failureReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("reason=\(failureReason)")
        }
        if let recoverySuggestion = nsError.localizedRecoverySuggestion,
           !recoverySuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("suggestion=\(recoverySuggestion)")
        }
        parts.append("domain=\(nsError.domain)")
        parts.append("code=\(nsError.code)")
        parts.append("type=\(String(reflecting: type(of: error)))")
        let reflected = String(reflecting: error).trimmingCharacters(in: .whitespacesAndNewlines)
        if !reflected.isEmpty {
            parts.append("reflected=\(reflected)")
        }
        let mirrorSummary = mirrorSummary(for: error)
        if !mirrorSummary.isEmpty {
            parts.append("mirror=\(mirrorSummary)")
        }
        return parts.joined(separator: " | ")
    }

    private func mirrorSummary(for error: Error) -> String {
        let mirror = Mirror(reflecting: error)
        guard !mirror.children.isEmpty else { return "" }

        return mirror.children
            .map { child in
                let label = child.label ?? "value"
                return "\(label)=\(String(reflecting: child.value))"
            }
            .joined(separator: ", ")
    }

    private func appendProbe(_ base: String, probe: String?) -> String {
        guard let probe, !probe.isEmpty else { return base }
        return "\(base) | \(probe)"
    }

    private func probeQueueFailureDetails(endpoint: String, input: Payload) async -> String? {
        guard !apiKey.isEmpty else { return "probe skipped: missing API key" }
        guard let url = URL(string: "https://queue.fal.run/\(endpoint)") else {
            return "probe skipped: invalid URL for endpoint \(endpoint)"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? input.json()

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return "probe response was not HTTPURLResponse"
            }

            let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>"
            let compactBody = bodyText
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")

            let prefix = String(compactBody.prefix(600))
            if (200...299).contains(http.statusCode) {
                return "probe status=\(http.statusCode) body=\(prefix)"
            }
            return "probe status=\(http.statusCode) body=\(prefix)"
        } catch {
            return "probe transport error: \(debugReason(for: error))"
        }
    }

}

private extension Data {
    nonisolated func dataURI() -> String {
        "data:\(mimeTypeGuess());base64,\(base64EncodedString())"
    }

    nonisolated func mimeTypeGuess() -> String {
        if starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }

        // HEIC/HEIF files use ISO BMFF with "ftyp" then a brand such as heic/heif.
        if count >= 12, let boxType = String(data: subdata(in: 4..<8), encoding: .ascii), boxType == "ftyp",
           let brand = String(data: subdata(in: 8..<12), encoding: .ascii), brand.lowercased().hasPrefix("hei") {
            return "image/heic"
        }

        return "application/octet-stream"
    }
}

enum FalServiceError: LocalizedError {
    case invalidResponse
    case missingAPIKey
    case networkError
    case generationFailed(reason: String?)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from fal.ai"
        case .missingAPIKey: return "Missing FAL API key"
        case .networkError: return "Network error while calling fal.ai"
        case .generationFailed(let reason):
            if let reason, !reason.isEmpty {
                return "fal.ai generation failed: \(reason)"
            }
            return "fal.ai generation failed"
        case .timeout: return "fal.ai request timed out"
        }
    }
}
