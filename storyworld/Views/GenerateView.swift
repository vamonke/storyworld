import SwiftUI

struct GenerateView: View {
    @Environment(ProjectState.self) private var state
    @State private var scenePrompt: String = ""
    @State private var isGenerating = false
    @State private var progress = 0.0

    private let videoClient = VideoGenerationClient()

    var body: some View {
        VStack(spacing: 24) {
            Text("Generate Video")
                .font(.largeTitle.bold())

            // Shot preview strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(state.shots) { shot in
                        Image(uiImage: shot.capturedFrame)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(height: 90)
            .padding(.horizontal)

            // Scene prompt
            VStack(alignment: .leading, spacing: 8) {
                Text("Scene Description")
                    .font(.headline)

                TextEditor(text: $scenePrompt)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.gray.opacity(0.3))
                    )
            }
            .padding(.horizontal)

            if isGenerating {
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal)

                    Text("Generating cinematic video...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await generate() }
                } label: {
                    Label("Generate Video", systemImage: "film")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(state.shots.isEmpty ? .gray : .blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(state.shots.isEmpty)
                .padding(.horizontal)
            }

            Button("Back to AR Director") {
                state.flowState = .arDirector
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.top)
        .onAppear {
            scenePrompt = state.project.scenePrompt
        }
    }

    private func generate() async {
        isGenerating = true
        state.project.scenePrompt = scenePrompt

        let frames = state.shots.map(\.capturedFrame)
        let prompt = scenePrompt.isEmpty ? "A cinematic animated scene with stylized characters" : scenePrompt

        // Simulate progress updates
        let progressTask = Task {
            while !Task.isCancelled && progress < 0.9 {
                try? await Task.sleep(for: .seconds(3))
                progress += 0.05
            }
        }

        do {
            let videoURL = try await videoClient.generateVideo(frames: frames, scenePrompt: prompt)
            progressTask.cancel()
            progress = 1.0
            state.project.generatedVideoURL = videoURL
            state.flowState = .playback
        } catch {
            progressTask.cancel()
            state.errorMessage = error.localizedDescription
            isGenerating = false
            progress = 0
        }
    }
}
