import SwiftUI
import RealityKit
import ARKit

struct ARDirectorView: View {
    @Environment(ProjectState.self) private var state
    @State private var arManager = ARSessionManager()
    @State private var placedCharacters = false
    @State private var statusMessage = "Point at a flat surface"
    @State private var pendingEntities: [ModelEntity] = []
    @State private var currentPlacementIndex = 0
    @State private var scaleValue: Double = 1.0

    var body: some View {
        ZStack {
            ARViewContainer(arManager: arManager)
                .ignoresSafeArea()
                .onTapGesture {
                    handleTap()
                }
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            guard !placedCharacters else { return }
                            let sensitivity: Float = .pi / 180
                            let deltaX = Float(value.translation.width)
                            arManager.previewYRotation = deltaX * sensitivity
                        }
                )

            // Crosshair + scale slider during placement
            if !placedCharacters {
                // Crosshair
                Circle()
                    .stroke(arManager.hasValidPlacement ? Color.green : Color.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .fill(arManager.hasValidPlacement ? Color.green.opacity(0.3) : Color.white.opacity(0.1))
                            .frame(width: 10, height: 10)
                    )

                // Vertical scale slider on the right edge
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption2)
                            .foregroundStyle(.white)
                        Slider(value: $scaleValue, in: 0.2...3.0)
                            .frame(width: 180)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 30, height: 180)
                            .onChange(of: scaleValue) { _, newValue in
                                arManager.previewScaleMultiplier = Float(newValue)
                            }
                        Image(systemName: "minus")
                            .font(.caption2)
                            .foregroundStyle(.white)
                        Text(String(format: "%.1fx", scaleValue))
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 40)
                    .padding(.trailing, 8)
                }
            }

            VStack {
                // Top bar
                HStack {
                    Button {
                        arManager.stopSession()
                        state.flowState = .welcome
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                    }

                    Spacer()

                    // Placement progress
                    Text(placedCharacters ? "Placement complete" : "Place \(currentPlacementIndex + 1)/\(max(pendingEntities.count, 1))")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())

                    Spacer()
                }
                .padding()

                Spacer()

                // Status message
                Text(statusMessage)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            arManager.startSession()
            loadEntities()
        }
        .onDisappear {
            arManager.stopSession()
        }
    }

    // Load all character entities up front, then show preview for the first one
    private func loadEntities() {
        Task {
            var entities: [ModelEntity] = []
            for character in state.characters {
                let charEntity = CharacterEntity(character: character)
                let entity = await charEntity.loadOrCreatePlaceholder()
                entities.append(entity)
            }
            pendingEntities = entities
            currentPlacementIndex = 0

            if let first = entities.first {
                arManager.startPreview(with: first)
                statusMessage = "Point at a surface, tap to place \(state.characters[0].name)"
            } else {
                statusMessage = "No AR entities available to place"
            }
        }
    }

    private func handleTap() {
        guard !placedCharacters,
              currentPlacementIndex < pendingEntities.count else { return }

        let entity = pendingEntities[currentPlacementIndex]
        guard arManager.placeAtCurrentPosition(entity) else {
            statusMessage = "No surface found — move your phone around"
            return
        }

        arManager.stopPreview()
        scaleValue = 1.0
        currentPlacementIndex += 1

        if currentPlacementIndex < pendingEntities.count {
            // Show preview for the next character
            let next = pendingEntities[currentPlacementIndex]
            arManager.startPreview(with: next)
            statusMessage = "Tap to place \(state.characters[currentPlacementIndex].name)"
        } else {
            // All characters placed
            placedCharacters = true
            statusMessage = "All entities placed. Walk around to inspect."
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    let arManager: ARSessionManager

    func makeUIView(context: Context) -> ARView {
        arManager.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
