import SwiftUI

struct CatNanoBananaTestView: View {
    let onClose: (() -> Void)?

    @State private var prompt = PromptExpander.cinematicMemoryPhotoEdit()
    @State private var originalImageData: Data?
    @State private var generatedImageData: Data?
    @State private var sourceLabel = "Not loaded"
    @State private var status = "Ready"
    @State private var lastModel = "None"
    @State private var isGenerating = false
    @State private var lastDuration: TimeInterval?
    @State private var errorMessage: String?

    private let falService = FalService()

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        if let onClose {
                            Button("Back") { onClose() }
                                .buttonStyle(.bordered)
                        }
                        Spacer()
                    }

                    Text("Cat Image Edit Test")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Run `fal-ai/bytedance/seedream/v4.5/edit`, `fal-ai/nano-banana/edit`, or `fal-ai/flux-2-pro/edit` with the same gallery prompt.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))

                    if Config.falKey.isEmpty {
                        Text("FAL key is missing. Set `FAL_KEY` in your .env before running.")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .padding(10)
                            .background(Color.yellow.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Text("Source: \(sourceLabel)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))

                    HStack(alignment: .top, spacing: 12) {
                        imageCard(
                            title: "Original",
                            imageData: originalImageData,
                            emptyLabel: "Missing cat image"
                        )
                        imageCard(
                            title: "Generated",
                            imageData: generatedImageData,
                            emptyLabel: isGenerating ? "Generating..." : "No result yet"
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prompt")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))

                        TextEditor(text: $prompt)
                            .frame(minHeight: 150)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    HStack(spacing: 10) {
                        Button(isGenerating ? "Running..." : "Run Seedream 4.5") {
                            runSeedream45()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGenerating || originalImageData == nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Run Nano Banana") {
                            runNanoBanana()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGenerating || originalImageData == nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Run Flux 2 Pro") {
                            runFlux2Pro()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGenerating || originalImageData == nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Reset Prompt") {
                            prompt = PromptExpander.cinematicMemoryPhotoEdit()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("Status: \(status)")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))

                    Text("Last model: \(lastModel)")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))

                    if let lastDuration {
                        Text(String(format: "Last run: %.2fs", lastDuration))
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
        }
        .task {
            loadCatIfNeeded()
        }
    }

    @ViewBuilder
    private func imageCard(title: String, imageData: Data?, emptyLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))

                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text(emptyLabel)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
    }

    private func loadCatIfNeeded() {
        guard originalImageData == nil else { return }

        guard let loaded = loadDefaultCatImageData() else {
            status = "Failed to load source image"
            errorMessage = "Could not find girl image in bundle or expected local paths."
            return
        }

        originalImageData = loaded.data
        sourceLabel = loaded.label
        status = "Ready"
    }

    private func runSeedream45() {
        guard let originalImageData else {
            errorMessage = "No source image loaded."
            return
        }

        let promptToSend = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptToSend.isEmpty else {
            errorMessage = "Prompt cannot be empty."
            return
        }

        let model = "fal-ai/bytedance/seedream/v4.5/edit"
        isGenerating = true
        lastModel = model
        status = "Calling \(model)..."
        errorMessage = nil
        lastDuration = nil
        generatedImageData = nil
        let start = Date()

        Task {
            do {
                let output = try await falService.cinematicShotSeedream45(
                    imageData: originalImageData,
                    prompt: promptToSend
                )
                await MainActor.run {
                    generatedImageData = output
                    isGenerating = false
                    lastDuration = Date().timeIntervalSince(start)
                    status = "Success (\(model))"
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    status = "Failed (\(model))"
                    errorMessage = "[\(model)] \(error.localizedDescription)"
                }
            }
        }
    }

    private func runNanoBanana() {
        guard let originalImageData else {
            errorMessage = "No source image loaded."
            return
        }

        let promptToSend = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptToSend.isEmpty else {
            errorMessage = "Prompt cannot be empty."
            return
        }

        let model = "fal-ai/nano-banana/edit"
        isGenerating = true
        lastModel = model
        status = "Calling \(model)..."
        errorMessage = nil
        lastDuration = nil
        generatedImageData = nil
        let start = Date()

        Task {
            do {
                let output = try await falService.cinematicShotNanoBanana(
                    imageData: originalImageData,
                    prompt: promptToSend
                )
                await MainActor.run {
                    generatedImageData = output
                    isGenerating = false
                    lastDuration = Date().timeIntervalSince(start)
                    status = "Success (\(model))"
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    status = "Failed (\(model))"
                    errorMessage = "[\(model)] \(error.localizedDescription)"
                }
            }
        }
    }

    private func runFlux2Pro() {
        guard let originalImageData else {
            errorMessage = "No source image loaded."
            return
        }

        let promptToSend = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptToSend.isEmpty else {
            errorMessage = "Prompt cannot be empty."
            return
        }

        let model = "fal-ai/flux-2-pro/edit"
        isGenerating = true
        lastModel = model
        status = "Calling \(model)..."
        errorMessage = nil
        lastDuration = nil
        generatedImageData = nil
        let start = Date()

        Task {
            do {
                let output = try await falService.cinematicShotFlux2Pro(
                    imageData: originalImageData,
                    prompt: promptToSend
                )
                await MainActor.run {
                    generatedImageData = output
                    isGenerating = false
                    lastDuration = Date().timeIntervalSince(start)
                    status = "Success (\(model))"
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    status = "Failed (\(model))"
                    errorMessage = "[\(model)] \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadDefaultCatImageData() -> (data: Data, label: String)? {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let candidates: [(label: String, url: URL?)] = [
            ("Bundle/girl.jpg", Bundle.main.url(forResource: "girl", withExtension: "jpg")),
            ("Bundle/girl.jpeg", Bundle.main.url(forResource: "girl", withExtension: "jpeg")),
            ("~/varicklim/pictures/girl", home.appendingPathComponent("varicklim/pictures/girl")),
            ("~/varicklim/pictures/girl.jpg", home.appendingPathComponent("varicklim/pictures/girl.jpg")),
            ("~/pictures/girl", home.appendingPathComponent("pictures/girl")),
            ("~/pictures/girl.jpg", home.appendingPathComponent("pictures/girl.jpg")),
            ("~/Pictures/girl", home.appendingPathComponent("Pictures/girl")),
            ("~/Pictures/girl.jpg", home.appendingPathComponent("Pictures/girl.jpg")),
            ("/Users/varicklim/pictures/girl", URL(fileURLWithPath: "/Users/varicklim/pictures/girl")),
            ("/Users/varicklim/pictures/girl.jpg", URL(fileURLWithPath: "/Users/varicklim/pictures/girl.jpg")),
        ]

        for candidate in candidates {
            guard let url = candidate.url else { continue }
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                return (data, candidate.label)
            }
        }

        return nil
    }
}

#Preview {
    CatNanoBananaTestView()
}
