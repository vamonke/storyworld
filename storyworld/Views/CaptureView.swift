import SwiftUI
import AVFoundation
import AudioToolbox

struct CaptureView: View {
    @Environment(ProjectState.self) private var state
    @State private var cameraService = CameraService()
    @State private var capturedImageData: Data?
    @State private var showingPreview = false
    @State private var characterName = ""

    var body: some View {
        ZStack {
            CameraPreviewView(cameraService: cameraService)
                .ignoresSafeArea()

            VStack {
                // Header
                HStack {
                    Button("Back") {
                        state.flowState = .welcome
                    }
                    .foregroundStyle(.white)

                    Spacer()

                    Text("Character \(state.characters.count + 1)")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Spacer()

                    if state.characters.count > 0 {
                        Button("Skip") {
                            state.flowState = .stylize
                        }
                        .foregroundStyle(.white)
                    }
                }
                .padding()
                .background(.black.opacity(0.3))

                Spacer()

                Text("Position a person in frame and tap capture")
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())

                // Capture button
                Button {
                    Task { await capturePhoto() }
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 4).frame(width: 84, height: 84))
                }
                .padding(.bottom, 40)
            }

            // Preview overlay
            if showingPreview, let imageData = capturedImageData,
               let uiImage = UIImage(data: imageData) {
                Color.black.opacity(0.7).ignoresSafeArea()

                VStack(spacing: 20) {
                    Text("Name this character")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    TextField("Character name", text: $characterName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 40)

                    HStack(spacing: 20) {
                        Button("Retake") {
                            showingPreview = false
                            capturedImageData = nil
                            characterName = ""
                        }
                        .buttonStyle(.bordered)

                        Button("Use This") {
                            let character = Character(
                                name: characterName.isEmpty ? "Character \(state.characters.count + 1)" : characterName,
                                originalPhoto: imageData
                            )
                            state.addCharacter(character)
                            showingPreview = false
                            capturedImageData = nil
                            characterName = ""

                            if state.characters.count >= 2 {
                                state.flowState = .stylize
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            setupCamera()
        }
        .onDisappear {
            cameraService.stop()
        }
    }

    private func setupCamera() {
        do {
            try cameraService.configure()
            cameraService.start()
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func capturePhoto() async {
        do {
            let data = try await cameraService.capturePhoto()
            capturedImageData = data
            showingPreview = true
            AudioServicesPlaySystemSound(SystemSoundID(1108))
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }
}

class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let cameraService: CameraService

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        let previewLayer = cameraService.previewLayer
        view.previewLayer = previewLayer
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}
