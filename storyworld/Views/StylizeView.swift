import SwiftUI

struct StylizeView: View {
    @Environment(ProjectState.self) private var state
    @State private var currentIndex = 0
    @State private var isStylizing = false
    @State private var stylizedPreview: UIImage?

    private let falClient = FalService()
    private let modelLoader = ModelLoader()

    var body: some View {
        VStack(spacing: 20) {
            Text("Stylize Characters")
                .font(.largeTitle.bold())

            if currentIndex < state.characters.count {
                let character = state.characters[currentIndex]

                Text(character.name)
                    .font(.title2)

                HStack(spacing: 20) {
                    // Original
                    VStack {
                        Text("Original")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let image = character.originalUIImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 160, maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Image(systemName: "arrow.right")
                        .font(.title)
                        .foregroundStyle(.secondary)

                    // Stylized
                    VStack {
                        Text("Stylized")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let image = stylizedPreview {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 160, maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else if isStylizing {
                            ProgressView("Stylizing...")
                                .frame(maxWidth: 160, maxHeight: 200)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.gray.opacity(0.2))
                                .frame(width: 160, height: 200)
                                .overlay(Text("Tap Stylize").foregroundStyle(.secondary))
                        }
                    }
                }

                if stylizedPreview != nil {
                    HStack(spacing: 16) {
                        Button("Regenerate") {
                            Task { await stylize() }
                        }
                        .buttonStyle(.bordered)

                        Button("Accept") {
                            acceptStylization()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if !isStylizing {
                    Button("Stylize") {
                        Task { await stylize() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    Text("All characters stylized!")
                        .font(.title2)
                    Text("Generating 3D models in the background...")
                        .foregroundStyle(.secondary)
                }

                Button("Continue to AR Director") {
                    state.flowState = .arDirector
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()
        }
        .padding()
    }

    private func stylize() async {
        guard currentIndex < state.characters.count else { return }
        isStylizing = true

        do {
            let imageData = state.characters[currentIndex].originalPhoto
            let stylizedData = try await falClient.stylizeImage(imageData: imageData)
            stylizedPreview = UIImage(data: stylizedData)
        } catch {
            state.errorMessage = error.localizedDescription
        }

        isStylizing = false
    }

    private func acceptStylization() {
        guard let preview = stylizedPreview,
              let data = preview.jpegData(compressionQuality: 0.9) else { return }

        state.characters[currentIndex].stylizedImage = data

        // Trigger 3D model generation in background
        let imageData = data
        let index = currentIndex
        Task {
            do {
                let (url, entity) = try await modelLoader.generateAndLoad(from: imageData)
                state.characters[index].modelURL = url
                state.characters[index].modelEntity = entity
            } catch {
                print("3D model generation failed: \(error)")
            }
        }

        stylizedPreview = nil
        currentIndex += 1
    }
}
