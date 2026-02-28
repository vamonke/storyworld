import SwiftUI
import AVKit
import Photos

struct PlaybackView: View {
    @Environment(ProjectState.self) private var state
    @State private var player: AVPlayer?
    @State private var savedToPhotos = false
    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Your Scene")
                .font(.largeTitle.bold())

            if let player {
                VideoPlayer(player: player)
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.gray.opacity(0.2))
                    .frame(height: 300)
                    .overlay(Text("No video available").foregroundStyle(.secondary))
                    .padding(.horizontal)
            }

            HStack(spacing: 16) {
                Button {
                    saveToPhotos()
                } label: {
                    Label(savedToPhotos ? "Saved!" : "Save to Photos", systemImage: savedToPhotos ? "checkmark" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(savedToPhotos)

                Button {
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            Button {
                state.reset()
            } label: {
                Label("Start Over", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
        .onAppear {
            if let url = state.project.generatedVideoURL {
                player = AVPlayer(url: url)
                player?.play()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = state.project.generatedVideoURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func saveToPhotos() {
        guard let url = state.project.generatedVideoURL else { return }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized else { return }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, _ in
                Task { @MainActor in
                    savedToPhotos = success
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
