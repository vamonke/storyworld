import SwiftUI
import RealityKit
import Combine
import AudioToolbox
import AVKit

enum TransformControlTarget: Equatable {
    case world
    case hero
    case villain

    var title: String {
        switch self {
        case .world: return "WORLD"
        case .hero: return "KNIGHT"
        case .villain: return "MONSTER"
        }
    }

    var characterSlot: CharacterSlot? {
        switch self {
        case .hero: return .hero
        case .villain: return .villain
        case .world: return nil
        }
    }
}

enum WorldPreset: String, CaseIterable, Identifiable {
    case dryGrass = "dry_grass_2k"
    case snow = "snow_2k"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dryGrass: return "DRY GRASS"
        case .snow: return "SNOW"
        }
    }

    var icon: String {
        switch self {
        case .dryGrass: return "leaf.fill"
        case .snow: return "snowflake"
        }
    }

    var environmentPrompt: String {
        switch self {
        case .dryGrass:
            return "epic fantasy battlefield with dry grass terrain"
        case .snow:
            return "epic fantasy battlefield covered in snow"
        }
    }
}

// MARK: - Root View

struct DirectorView: View {
    let onExit: (() -> Void)?
    @StateObject private var store: FilmDirectorStore
    @State private var arManager = ARSessionManager()
    @State private var baseEntities: [CharacterSlot: ModelEntity] = [:]
    @State private var currentPlacementSlot: CharacterSlot?
    @State private var placementStatusMessage = "Summon characters, then tap to place."
    @State private var scaleValue: Double = 1.0
    @State private var hasSurface = false
    @State private var showingGallery = false
    @State private var activeTransformTarget: TransformControlTarget?
    @State private var worldPlaneOffset: Double = -0.22
    @State private var selectedWorldPreset: WorldPreset = .dryGrass
    @State private var characterScaleValue: Double = 1.0
    @State private var characterYawValue: Double = 0.0

    init(onExit: (() -> Void)? = nil) {
        self.onExit = onExit
        _store = StateObject(wrappedValue: FilmDirectorStore(
            generationService: HybridGenerationService()
        ))
    }

    var body: some View {
        ZStack {
            // Real AR layer
            ARViewContainer(arManager: arManager)
                .ignoresSafeArea()
                .onTapGesture {
                    handlePlacementTap()
                }
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            guard currentPlacementSlot != nil else { return }
                            let sensitivity: Float = .pi / 180
                            let deltaX = Float(value.translation.width)
                            arManager.previewYRotation = deltaX * sensitivity
                        }
                )

            if currentPlacementSlot != nil {
                Circle()
                    .stroke(arManager.hasValidPlacement ? Color.green : Color.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .fill(arManager.hasValidPlacement ? Color.green.opacity(0.3) : Color.white.opacity(0.1))
                            .frame(width: 10, height: 10)
                    )

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

            // HUD overlay
            DirectorHUD(
                store: store,
                hasSurface: hasSurface,
                selectedWorldPreset: selectedWorldPreset,
                statusMessage: placementStatusMessage,
                onCaptureShot: captureShot,
                onCapturePhoto: capturePhoto,
                onOpenGallery: { showingGallery = true },
                onExitShooting: { store.dispatch(.exitShotMode) },
                onExitDirector: exitDirectorMode,
                onTapWorldBadge: openWorldControls,
                onTapHeroBadge: { openCharacterControls(slot: .hero) },
                onTapVillainBadge: { openCharacterControls(slot: .villain) }
            )

            if let target = activeTransformTarget {
                TransformControlPanel(
                    target: target,
                    worldOffset: $worldPlaneOffset,
                    selectedWorldPreset: $selectedWorldPreset,
                    characterScale: $characterScaleValue,
                    characterYaw: $characterYawValue,
                    hasSurface: hasSurface,
                    worldStatus: store.session.environment?.status ?? .idle,
                    onDismiss: { activeTransformTarget = nil },
                    onWorldOffsetChanged: { arManager.setWorldPlaneYOffset(Float($0)) },
                    onSetWorld: {
                        store.dispatch(
                            .setEnvironment(
                                prompt: selectedWorldPreset.environmentPrompt,
                                localSkyboxResourceName: selectedWorldPreset.rawValue
                            )
                        )
                    },
                    onCharacterScaleChanged: { value, slot in
                        arManager.setCharacterScaleMultiplier(Float(value), slot: slot)
                    },
                    onCharacterYawChanged: { value, slot in
                        arManager.setCharacterYawDegrees(Float(value), slot: slot)
                    },
                    onRemoveWorld: removeWorld,
                    onRemoveCharacter: removeCharacter
                )
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .fullScreenCover(isPresented: $showingGallery) {
            PhotoGalleryView(store: store)
        }
        .onAppear {
            arManager.startSession()
            store.arScene = arManager
            syncPlacementPreview()
        }
        .onDisappear {
            arManager.stopSession()
        }
        .onChange(of: showingGallery) { _, isShowing in
            if isShowing {
                arManager.stopSession()
            } else {
                arManager.startSession()
                syncPlacementPreview()
            }
        }
        .onReceive(store.$session) { _ in
            syncPlacementPreview()
        }
        .onReceive(Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()) { _ in
            let detected = arManager.hasValidPlacement
            if detected != hasSurface {
                hasSurface = detected
            }
        }
    }

    private func modelURL(for slot: CharacterSlot) -> URL? {
        switch slot {
        case .hero:
            return store.session.hero?.modelURL
        case .villain:
            return store.session.villain?.modelURL
        }
    }

    private func characterName(for slot: CharacterSlot) -> String {
        switch slot {
        case .hero:
            return store.session.hero?.name ?? "Knight"
        case .villain:
            return store.session.villain?.name ?? "Monster"
        }
    }

    private func nextPlacementSlot() -> CharacterSlot? {
        let heroNeedsPlacement = store.session.hero?.status == .ready && store.session.hero?.anchorIdentifier == nil
        let villainNeedsPlacement = store.session.villain?.status == .ready && store.session.villain?.anchorIdentifier == nil

        if heroNeedsPlacement { return .hero }
        if villainNeedsPlacement { return .villain }
        return nil
    }

    private func syncPlacementPreview() {
        guard let slot = nextPlacementSlot() else {
            currentPlacementSlot = nil
            arManager.stopPreview()
            return
        }

        if currentPlacementSlot == slot {
            return
        }

        currentPlacementSlot = slot
        arManager.previewScaleMultiplier = Float(scaleValue)

        Task {
            do {
                let sourceEntity: ModelEntity
                if let cached = baseEntities[slot] {
                    sourceEntity = cached
                } else {
                    guard let url = modelURL(for: slot) else {
                        placementStatusMessage = "Missing model URL for \(characterName(for: slot))"
                        return
                    }
                    let loaded = try await ModelEntity(contentsOf: url)
                    loaded.generateCollisionShapes(recursive: true)
                    baseEntities[slot] = loaded
                    sourceEntity = loaded
                }

                arManager.stopPreview()
                arManager.startPreview(with: sourceEntity)
                placementStatusMessage = "Tap surface to place \(characterName(for: slot))"
            } catch {
                placementStatusMessage = "Failed to load model for \(characterName(for: slot))"
            }
        }
    }

    private func handlePlacementTap() {
        guard let slot = currentPlacementSlot, let source = baseEntities[slot] else { return }

        let entityToPlace = source.clone(recursive: true)
        guard arManager.placeAtCurrentPosition(entityToPlace) else {
            placementStatusMessage = "No surface found. Move phone to detect a plane."
            return
        }

        switch slot {
        case .hero:
            arManager.registerPlacedCharacter(entityToPlace, slot: .hero)
            store.dispatch(.placeHero(anchorId: UUID()))
        case .villain:
            arManager.registerPlacedCharacter(entityToPlace, slot: .villain)
            store.dispatch(.placeVillain(anchorId: UUID()))
        }

        scaleValue = 1.0
        arManager.previewScaleMultiplier = 1.0
        placementStatusMessage = ""
        syncPlacementPreview()
    }

    private func captureShot(angle: CameraAngle) {
        Task {
            guard let snapshot = await arManager.captureSnapshot() else { return }

            var characters: [CharacterSlot] = []
            if store.session.hero?.status == .placed { characters.append(.hero) }
            if store.session.villain?.status == .placed { characters.append(.villain) }
            if characters.isEmpty { characters = [.hero, .villain] }

            store.dispatch(.captureShot(
                angle: angle,
                image: snapshot,
                charactersInFrame: characters
            ))
            AudioServicesPlaySystemSound(SystemSoundID(1108))
        }
    }

    private func capturePhoto() {
        Task {
            guard let snapshot = await arManager.captureSnapshot() else { return }
            let resized = snapshot.scaledTo(maxDimension: 1080)
            store.dispatch(.captureMemoryPhoto(image: resized))
            AudioServicesPlaySystemSound(SystemSoundID(1108))
        }
    }

    private func openWorldControls() {
        if activeTransformTarget == .world {
            activeTransformTarget = nil
            return
        }
        worldPlaneOffset = Double(arManager.worldPlaneYOffsetValue)
        activeTransformTarget = .world
    }

    private func openCharacterControls(slot: CharacterSlot) {
        let target: TransformControlTarget = (slot == .hero) ? .hero : .villain
        if activeTransformTarget == target {
            activeTransformTarget = nil
            return
        }
        guard arManager.hasPlacedCharacter(slot) else {
            placementStatusMessage = "Place \(characterName(for: slot)) first to edit."
            return
        }
        characterScaleValue = Double(arManager.characterScaleMultiplier(for: slot))
        characterYawValue = Double(arManager.characterYawDegrees(for: slot))
        activeTransformTarget = target
    }

    private func removeWorld() {
        store.dispatch(.clearEnvironment)
        activeTransformTarget = nil
        placementStatusMessage = ""
    }

    private func removeCharacter(slot: CharacterSlot) {
        store.dispatch(.clearCharacter(slot: slot))
        activeTransformTarget = nil
        placementStatusMessage = ""
    }

    private func exitDirectorMode() {
        store.dispatch(.reset)
        activeTransformTarget = nil
        showingGallery = false
        placementStatusMessage = ""
        onExit?()
    }
}

// MARK: - HUD

struct DirectorHUD: View {
    @ObservedObject var store: FilmDirectorStore
    let hasSurface: Bool
    let selectedWorldPreset: WorldPreset
    let statusMessage: String
    let onCaptureShot: (CameraAngle) -> Void
    let onCapturePhoto: () -> Void
    let onOpenGallery: () -> Void
    let onExitShooting: () -> Void
    let onExitDirector: () -> Void
    let onTapWorldBadge: () -> Void
    let onTapHeroBadge: () -> Void
    let onTapVillainBadge: () -> Void

    var body: some View {
        ZStack {
            // Top — phase + generation badges
            VStack {
                HStack {
                    Button(action: onExitDirector) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                            Text("EXIT")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(.black.opacity(0.55))
                                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: onOpenGallery) {
                        HStack(spacing: 5) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 10, weight: .semibold))
                            Text("GALLERY")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(.black.opacity(0.55))
                                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)
                .padding(.horizontal, 20)

                GenerationStatusRow(
                    session: store.session,
                    onTapWorld: onTapWorldBadge,
                    onTapHero: onTapHeroBadge,
                    onTapVillain: onTapVillainBadge
                )
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(.top, 6)
                        .padding(.horizontal, 20)
                }

                Spacer()
            }

            // Bottom — contextual action buttons
            VStack {
                Spacer()
                ActionPanel(
                    store: store,
                    hasSurface: hasSurface,
                    selectedWorldPreset: selectedWorldPreset,
                    onCaptureShot: onCaptureShot,
                    onCapturePhoto: onCapturePhoto,
                    onExitShooting: onExitShooting
                )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            // Notifications (top-center)
            VStack {
                ForEach(store.notifications) { n in
                    NotificationToast(notification: n)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: store.notifications.count)
                .padding(.top, 116)
                Spacer()
            }

            // Shot strip (visible in takingShots + generatingClip)
            if [.takingShots, .generatingClip, .reviewingClip].contains(store.session.phase) {
                VStack {
                    Spacer()
                    ShotStrip(shots: store.session.shots, store: store)
                        .padding(.bottom, 84)
                }
            }
        }
    }
}

// MARK: - Phase Badge

struct PhaseBadge: View {
    let phase: ProductionPhase

    var body: some View {
        HStack(spacing: 8) {
            if [.generatingWorld, .generatingCharacter, .generatingClip].contains(phase) {
                BreathingDot()
            } else {
                Image(systemName: phase.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(phase.displayName.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.black.opacity(0.55))
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
        )
        .animation(.easeInOut(duration: 0.3), value: phase)
    }
}

struct BreathingDot: View {
    @State private var scale = 0.6
    var body: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 6, height: 6)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    scale = 1.2
                }
            }
    }
}

// MARK: - Generation Status Row (hero / villain / env badges)

struct GenerationStatusRow: View {
    let session: FilmSession
    let onTapWorld: () -> Void
    let onTapHero: () -> Void
    let onTapVillain: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AssetBadge(label: "World", status: session.environment?.status ?? .idle, icon: "globe", action: onTapWorld)
            if let hero = session.hero {
                AssetBadge(label: hero.name, status: hero.status, icon: "figure.stand", action: onTapHero)
            }
            if let villain = session.villain {
                AssetBadge(label: villain.name, status: villain.status, icon: "flame.fill", action: onTapVillain)
            }
            Spacer()
        }
    }
}

struct SurfaceBadge: View {
    let hasSurface: Bool

    private var statusColor: Color {
        hasSurface ? .green : .orange
    }

    private var icon: String {
        hasSurface ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var label: String {
        hasSurface ? "SURFACE" : "NO SURFACE"
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(statusColor)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.black.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(statusColor.opacity(0.25), lineWidth: 0.5))
        )
    }
}

struct AssetBadge: View {
    let label: String
    let status: GenerationStatus
    let icon: String
    let action: () -> Void

    var statusColor: Color {
        switch status {
        case .idle, .queued:   return .white.opacity(0.3)
        case .generating:      return .orange
        case .ready:           return .yellow
        case .placed:          return .green
        case .failed:          return .red
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(statusColor)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(statusColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.black.opacity(0.4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(statusColor.opacity(0.25), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }
}

struct TransformControlPanel: View {
    let target: TransformControlTarget
    @Binding var worldOffset: Double
    @Binding var selectedWorldPreset: WorldPreset
    @Binding var characterScale: Double
    @Binding var characterYaw: Double
    let hasSurface: Bool
    let worldStatus: GenerationStatus
    let onDismiss: () -> Void
    let onWorldOffsetChanged: (Double) -> Void
    let onSetWorld: () -> Void
    let onCharacterScaleChanged: (Double, CharacterSlot) -> Void
    let onCharacterYawChanged: (Double, CharacterSlot) -> Void
    let onRemoveWorld: () -> Void
    let onRemoveCharacter: (CharacterSlot) -> Void

    var body: some View {
        GlassPanel {
            VStack(spacing: 12) {
                HStack {
                    PanelTitle("ADJUST \(target.title)")
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(8)
                            .background(Circle().fill(.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }

                if target == .world {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WORLD TYPE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.7))

                        HStack(spacing: 8) {
                            ForEach(WorldPreset.allCases) { preset in
                                let isSelected = preset == selectedWorldPreset
                                Button {
                                    selectedWorldPreset = preset
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: preset.icon)
                                            .font(.system(size: 10, weight: .semibold))
                                        Text(preset.title)
                                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                            .tracking(1.1)
                                    }
                                    .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.8))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected ? Color.white : Color.white.opacity(0.08))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(.white.opacity(isSelected ? 0.0 : 0.14), lineWidth: 0.5)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(worldStatus == .generating)
                            }
                        }
                    }

                    DirectorButton(label: "SET WORLD", icon: "globe.europe.africa.fill", style: .secondary) {
                        onSetWorld()
                    }
                    .disabled(!hasSurface || worldStatus == .generating || worldStatus == .ready || worldStatus == .placed)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("WORLD Y")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.7))
                        Slider(value: $worldOffset, in: -0.6...0.2, step: 0.01)
                            .onChange(of: worldOffset) { _, newValue in
                                onWorldOffsetChanged(newValue)
                            }
                        Text(String(format: "%.2f m", worldOffset))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    if worldStatus == .ready || worldStatus == .placed {
                        DirectorButton(
                            label: "REMOVE WORLD",
                            icon: "trash",
                            style: .ghost,
                            action: onRemoveWorld
                        )
                    }
                } else if let slot = target.characterSlot {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SIZE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.7))
                        Slider(value: $characterScale, in: 0.2...3.0, step: 0.01)
                            .onChange(of: characterScale) { _, newValue in
                                onCharacterScaleChanged(newValue, slot)
                            }
                        Text(String(format: "%.2fx", characterScale))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("ORIENTATION")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.7))
                        Slider(value: $characterYaw, in: -180...180, step: 1)
                            .onChange(of: characterYaw) { _, newValue in
                                onCharacterYawChanged(newValue, slot)
                            }
                        Text(String(format: "%.0f°", characterYaw))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    DirectorButton(
                        label: "REMOVE \(target.title)",
                        icon: "trash",
                        style: .ghost
                    ) {
                        onRemoveCharacter(slot)
                    }
                }
            }
        }
    }
}

// MARK: - Action Panel (phase-driven buttons)

struct ActionPanel: View {
    @ObservedObject var store: FilmDirectorStore
    let hasSurface: Bool
    let selectedWorldPreset: WorldPreset
    let onCaptureShot: (CameraAngle) -> Void
    let onCapturePhoto: () -> Void
    let onExitShooting: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            switch store.session.phase {

            case .idle:
                IdlePanel(store: store, hasSurface: hasSurface, selectedWorldPreset: selectedWorldPreset)

            case .generatingWorld:
                WaitingPanel(message: "Summoning the battlefield...", subtext: "Walk around to explore")

            case .placingWorld:
                IdlePanel(store: store, hasSurface: hasSurface, selectedWorldPreset: selectedWorldPreset)

            case .generatingCharacter:
                GeneratingCharacterPanel(session: store.session, store: store)

            case .placingCharacters:
                IdlePanel(store: store, hasSurface: hasSurface, selectedWorldPreset: selectedWorldPreset)

            case .takingShots:
                PhotoCapturePanel(
                    store: store,
                    hasSurface: hasSurface,
                    onCapturePhoto: onCapturePhoto,
                    onExitShooting: onExitShooting
                )

            case .generatingClip:
                WaitingPanel(message: "Rendering your film...", subtext: "Keep capturing shots")

            case .reviewingClip:
                ReviewPanel(store: store)
            }
        }
    }
}

// MARK: - Idle Panel

struct IdlePanel: View {
    @ObservedObject var store: FilmDirectorStore
    let hasSurface: Bool
    let selectedWorldPreset: WorldPreset
    @State private var showingCharacterPicker = false

    var body: some View {
        let worldDone = store.session.environment?.status == .ready || store.session.environment?.status == .placed
        let knightDone = store.session.hero?.status == .ready || store.session.hero?.status == .placed
        let monsterDone = store.session.villain?.status == .ready || store.session.villain?.status == .placed
        let worldGenerating = store.session.phase == .generatingWorld
        let knightGenerating = store.session.hero?.status == .queued || store.session.hero?.status == .generating
        let monsterGenerating = store.session.villain?.status == .queued || store.session.villain?.status == .generating
        let characterGenerating = knightGenerating || monsterGenerating || store.session.phase == .generatingCharacter

        GlassPanel {
            if showingCharacterPicker {
                VStack(spacing: 12) {
                    PanelTitle("ADD CHARACTER")

                    Text("Choose who to summon next.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    DirectorButton(label: "ADD KNIGHT", icon: "shield.fill", style: .primary) {
                        store.dispatch(.generateHero(prompt: "dark knight in obsidian armor"))
                        showingCharacterPicker = false
                    }
                    .disabled(!hasSurface || worldGenerating || knightDone || knightGenerating)

                    DirectorButton(label: "ADD MONSTER", icon: "flame.fill", style: .secondary) {
                        store.dispatch(.generateVillain(prompt: "fire demon with molten skin and curved horns"))
                        showingCharacterPicker = false
                    }
                    .disabled(!hasSurface || worldGenerating || monsterDone || monsterGenerating)

                    DirectorButton(label: "BACK", icon: "arrow.left", style: .ghost) {
                        showingCharacterPicker = false
                    }
                }
            } else {
                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        PanelTitle("SCENE SETUP")
                        Spacer()
                        SurfaceBadge(hasSurface: hasSurface)
                    }

                    HStack(spacing: 10) {
                        DirectorButton(label: "SET WORLD", icon: "globe.europe.africa.fill", style: .secondary) {
                            store.dispatch(
                                .setEnvironment(
                                    prompt: selectedWorldPreset.environmentPrompt,
                                    localSkyboxResourceName: selectedWorldPreset.rawValue
                                )
                            )
                        }
                        .disabled(!hasSurface || worldDone)

                        DirectorButton(label: "ADD CHARACTER", icon: "person.2.fill", style: .primary) {
                            showingCharacterPicker = true
                        }
                        .disabled(!hasSurface || worldGenerating || (knightDone && monsterDone))
                    }

                    if worldGenerating || characterGenerating {
                        Text(worldGenerating ? "Setting world..." : "Adding character...")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    if store.session.canShoot {
                        DirectorButton(label: "START SHOOTING", icon: "camera.aperture", style: .primary) {
                            store.dispatch(.enterShotMode)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Placing World

struct PlacingWorldPanel: View {
    @ObservedObject var store: FilmDirectorStore

    var body: some View {
        GlassPanel {
            VStack(spacing: 12) {
                PanelTitle("WORLD READY")
                Text("Generating characters in background")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                DirectorButton(label: "ENTER SHOT MODE", icon: "camera.aperture", style: .primary) {
                    store.dispatch(.enterShotMode)
                }
                .disabled(!store.session.canShoot)
            }
        }
    }
}

// MARK: - Generating Character Panel

struct GeneratingCharacterPanel: View {
    let session: FilmSession
    @ObservedObject var store: FilmDirectorStore

    var body: some View {
        GlassPanel {
            VStack(spacing: 14) {
                PanelTitle("SUMMONING")

                CharacterCard(
                    label: "KNIGHT",
                    icon: "figure.stand",
                    status: session.hero?.status ?? .idle
                )

                if session.heroReady {
                    DirectorButton(label: "PLACE NOW", icon: "plus.viewfinder", style: .primary) {
                        store.dispatch(.enterShotMode)
                    }
                }
            }
        }
    }
}

struct CharacterCard: View {
    let label: String
    let icon: String
    let status: GenerationStatus

    var statusText: String {
        switch status {
        case .idle:       return "WAITING"
        case .queued:     return "QUEUED"
        case .generating: return "GENERATING"
        case .ready:      return "READY"
        case .placed:     return "PLACED"
        case .failed:     return "FAILED"
        }
    }

    var accent: Color {
        switch status {
        case .ready, .placed: return .yellow
        case .generating:     return .orange
        case .failed:         return .red
        default:              return .white.opacity(0.3)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(accent)

            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.7))

            Text(statusText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(accent)

            if status == .generating {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.6)
                    .tint(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.2), lineWidth: 0.5))
        )
    }
}

// MARK: - Placing Characters Panel

struct PlacingCharactersPanel: View {
    @ObservedObject var store: FilmDirectorStore

    var body: some View {
        GlassPanel {
            VStack(spacing: 14) {
                PanelTitle("PLACE CHARACTERS")
                Text("Tap on AR surface to place highlighted character")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Drag to rotate preview. Use right slider to scale.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))

                if store.session.canShoot {
                    DirectorButton(label: "START SHOOTING", icon: "camera.aperture", style: .primary) {
                        store.dispatch(.enterShotMode)
                    }
                }
            }
        }
    }
}

// MARK: - Shot Panel

struct ShotPanel: View {
    @ObservedObject var store: FilmDirectorStore
    let onCaptureShot: (CameraAngle) -> Void

    let angles: [CameraAngle] = [
        .wideEstablishing, .mediumTwoShot, .closeUpFace,
        .overTheShoulder, .lowAngleHeroic, .insertDetail
    ]

    var body: some View {
        VStack(spacing: 10) {
            // Shot type buttons — 3 per row
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(angles, id: \.self) { angle in
                    ShotButton(angle: angle) {
                        onCaptureShot(angle)
                    }
                }
            }

            // Generate film CTA (appears after 3+ shots)
            if store.session.canGenerate {
                DirectorButton(
                    label: "GENERATE FILM (\(store.session.shots.count) SHOTS)",
                    icon: "film.stack",
                    style: .primary
                ) {
                    let shotIds = store.session.shots.map(\.id)
                    store.dispatch(.generateClip(shotIds: shotIds, style: .epicFantasy))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

struct PhotoCapturePanel: View {
    @ObservedObject var store: FilmDirectorStore
    let hasSurface: Bool
    let onCapturePhoto: () -> Void
    let onExitShooting: () -> Void

    var body: some View {
        GlassPanel {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    PanelTitle("PHOTO MODE")
                    Spacer()
                    SurfaceBadge(hasSurface: hasSurface)
                }

                HStack(spacing: 10) {
                    DirectorButton(
                        label: "TAKE PHOTO",
                        icon: "camera.fill",
                        style: .primary,
                        action: onCapturePhoto
                    )
                }

                DirectorButton(
                    label: "EXIT SHOOTING",
                    icon: "xmark.circle",
                    style: .ghost,
                    action: onExitShooting
                )

                if store.session.canGenerate {
                    DirectorButton(
                        label: "GENERATE FILM (\(store.session.shots.count) SHOTS)",
                        icon: "film.stack",
                        style: .primary
                    ) {
                        let shotIds = store.session.shots.map(\.id)
                        store.dispatch(.generateClip(shotIds: shotIds, style: .epicFantasy))
                    }
                }
            }
        }
    }
}

enum GalleryMediaKind {
    case photo
    case video
}

struct GalleryMediaItem: Identifiable {
    let id: UUID
    let kind: GalleryMediaKind
    let capturedAt: Date
    let previewImage: UIImage?
    let processingStatus: MemoryPhotoProcessingStatus
    let processingError: String?
    let photoId: UUID?
    let videoURL: URL?

    nonisolated init(photo: ARMemoryPhoto) {
        self.id = photo.id
        self.kind = .photo
        self.capturedAt = photo.capturedAt
        self.previewImage = UIImage(data: photo.imageData)
        self.processingStatus = photo.processingStatus
        self.processingError = photo.processingError
        self.photoId = photo.id
        self.videoURL = nil
    }

    nonisolated init(video: ARMemoryVideo) {
        self.id = video.id
        self.kind = .video
        self.capturedAt = video.capturedAt
        self.previewImage = UIImage(data: video.thumbnailImageData)
        self.processingStatus = video.processingStatus
        self.processingError = video.processingError
        self.photoId = video.sourcePhotoId
        self.videoURL = video.videoURL
    }

    var isVideo: Bool {
        kind == .video
    }
}

struct PhotoGalleryView: View {
    @ObservedObject var store: FilmDirectorStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMediaIndex: Int?

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var mediaItems: [GalleryMediaItem] {
        let photoItems = store.session.photos.map(GalleryMediaItem.init(photo:))
        let videoItems = store.session.videos.map(GalleryMediaItem.init(video:))
        return (photoItems + videoItems).sorted { $0.capturedAt > $1.capturedAt }
    }

    private var processingCount: Int { store.session.processingMediaCount }
    private var failedCount: Int { store.session.failedMediaCount }

    var body: some View {
        NavigationStack {
            Group {
                if mediaItems.isEmpty {
                    ContentUnavailableView("No Media Yet", systemImage: "photo.on.rectangle.angled")
                } else {
                    VStack(spacing: 8) {
                        if processingCount > 0 || failedCount > 0 {
                            GalleryProcessingSummaryView(
                                processingCount: processingCount,
                                failedCount: failedCount
                            )
                            .padding(.horizontal, 12)
                        }

                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, item in
                                    Button {
                                        selectedMediaIndex = index
                                    } label: {
                                        ZStack {
                                            if let image = item.previewImage {
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(height: 110)
                                                    .frame(maxWidth: .infinity)
                                                    .clipped()
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            } else {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(.white.opacity(0.08))
                                                    .frame(height: 110)
                                                    .overlay {
                                                        Image(systemName: item.isVideo ? "video.fill" : "photo")
                                                            .foregroundStyle(.white.opacity(0.55))
                                                    }
                                            }

                                            if item.processingStatus == .processing {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(.black.opacity(0.35))
                                                ProgressView()
                                                    .tint(.white)
                                            }
                                        }
                                        .overlay(alignment: .center) {
                                            if item.isVideo {
                                                Image(systemName: "play.circle.fill")
                                                    .font(.system(size: 24, weight: .semibold))
                                                    .foregroundStyle(.white.opacity(0.92))
                                                    .shadow(radius: 4)
                                            }
                                        }
                                        .overlay(alignment: .topTrailing) {
                                            if item.processingStatus != .ready {
                                                GalleryPhotoStatusBadge(status: item.processingStatus)
                                                    .padding(6)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        if let error = item.processingError, item.processingStatus == .failed {
                                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                        }

                                        Button(role: .destructive) {
                                            if item.isVideo {
                                                store.dispatch(.deleteMemoryVideo(id: item.id))
                                            } else {
                                                store.dispatch(.deleteMemoryPhoto(id: item.id))
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(12)
                        }
                    }
                }
            }
            .navigationTitle("Gallery")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if processingCount > 0 {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("\(processingCount)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                    }
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { selectedMediaIndex != nil },
                    set: { isPresented in
                        if !isPresented { selectedMediaIndex = nil }
                    }
                )
            ) {
                if let selectedMediaIndex {
                    GalleryMediaViewer(
                        mediaItems: mediaItems,
                        initialIndex: selectedMediaIndex
                    ) { photoId, prompt in
                        store.dispatch(.animateMemoryPhoto(id: photoId, prompt: prompt))
                    }
                }
            }
        }
    }
}

struct GalleryProcessingSummaryView: View {
    let processingCount: Int
    let failedCount: Int

    var body: some View {
        HStack(spacing: 10) {
            if processingCount > 0 {
                Label("\(processingCount) processing", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
            if failedCount > 0 {
                Label("\(failedCount) failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.1), lineWidth: 0.5))
        )
    }
}

struct GalleryPhotoStatusBadge: View {
    let status: MemoryPhotoProcessingStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .processing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
            } else {
                Image(systemName: status.badgeIcon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(status.badgeText)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Capsule().fill(status.badgeColor.opacity(0.9)))
    }
}

struct GalleryMediaViewer: View {
    let mediaItems: [GalleryMediaItem]
    let initialIndex: Int
    let onAnimatePhoto: (UUID, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int
    @State private var showingAnimatePrompt = false
    @State private var animatePrompt = ""

    init(mediaItems: [GalleryMediaItem], initialIndex: Int, onAnimatePhoto: @escaping (UUID, String) -> Void) {
        self.mediaItems = mediaItems
        self.initialIndex = initialIndex
        self.onAnimatePhoto = onAnimatePhoto
        _selectedIndex = State(initialValue: initialIndex)
    }

    private var selectedItem: GalleryMediaItem? {
        guard mediaItems.indices.contains(selectedIndex) else { return nil }
        return mediaItems[selectedIndex]
    }

    private var selectedPhotoId: UUID? {
        guard let item = selectedItem, item.kind == .photo else { return nil }
        return item.photoId
    }

    private var canAnimateSelectedItem: Bool {
        guard let item = selectedItem else { return false }
        return item.kind == .photo && item.processingStatus == .ready
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                TabView(selection: $selectedIndex) {
                    ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, item in
                        ZStack {
                            Color.black.ignoresSafeArea()
                            switch item.kind {
                            case .photo:
                                if let image = item.previewImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .padding()
                                } else {
                                    Image(systemName: "photo")
                                        .font(.system(size: 36))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            case .video:
                                if item.processingStatus == .ready, let url = item.videoURL {
                                    GalleryVideoPlayer(url: url)
                                        .padding(.vertical, 50)
                                } else {
                                    VStack(spacing: 14) {
                                        if let image = item.previewImage {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFit()
                                                .padding(.horizontal)
                                        }
                                        if item.processingStatus == .processing {
                                            ProgressView("Generating animation...")
                                                .tint(.white)
                                                .foregroundStyle(.white.opacity(0.85))
                                        } else {
                                            Text("Animation unavailable")
                                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                }
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .onChange(of: selectedIndex) { _, _ in
                    showingAnimatePrompt = false
                    animatePrompt = ""
                }

                if canAnimateSelectedItem {
                    VStack(spacing: 8) {
                        Button {
                            showingAnimatePrompt.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("ANIMATE")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .tracking(1)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(.white.opacity(0.14))
                                    .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
                            )
                        }
                        .buttonStyle(.plain)

                        if showingAnimatePrompt {
                            HStack(spacing: 8) {
                                DarkTextField(placeholder: "Describe motion...", text: $animatePrompt)
                                Button("Submit") {
                                    submitAnimatePrompt()
                                }
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.white)
                                )
                                .disabled(animatePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.black.opacity(0.65))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12), lineWidth: 0.5))
                            )
                            .padding(.horizontal, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.bottom, 50)
                    .animation(.easeInOut(duration: 0.2), value: showingAnimatePrompt)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(selectedIndex + 1)/\(mediaItems.count)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    private func submitAnimatePrompt() {
        guard let photoId = selectedPhotoId else { return }
        let trimmedPrompt = animatePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }
        onAnimatePhoto(photoId, trimmedPrompt)
        animatePrompt = ""
        showingAnimatePrompt = false
    }
}

struct GalleryVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear {
            if player == nil {
                player = AVPlayer(url: url)
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

private extension MemoryPhotoProcessingStatus {
    var badgeText: String {
        switch self {
        case .processing: return "PROCESSING"
        case .ready: return "READY"
        case .failed: return "FAILED"
        }
    }

    var badgeIcon: String {
        switch self {
        case .processing: return "sparkles"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var badgeColor: Color {
        switch self {
        case .processing: return .blue
        case .ready: return .green
        case .failed: return .red
        }
    }
}

struct ShotButton: View {
    let angle: CameraAngle
    let action: () -> Void

    @State private var flashing = false

    var body: some View {
        Button(action: {
            withAnimation(.easeOut(duration: 0.1)) { flashing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { flashing = false }
            action()
        }) {
            VStack(spacing: 5) {
                Image(systemName: angle.icon)
                    .font(.system(size: 16))
                Text(angle.displayName.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(flashing ? .black : .white)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(flashing ? Color.white : Color.white.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: flashing)
    }
}

// MARK: - Shot Strip

struct ShotStrip: View {
    let shots: [ARShot]
    @ObservedObject var store: FilmDirectorStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(shots) { shot in
                    ShotThumbnail(shot: shot) {
                        store.dispatch(.deleteShot(id: shot.id))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 70)
    }
}

struct ShotThumbnail: View {
    let shot: ARShot
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Frame
            RoundedRectangle(cornerRadius: 6)
                .fill(.black.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.15), lineWidth: 0.5))
                .frame(width: 55, height: 55)
                .overlay(
                    Text("\(shot.index)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(4),
                    alignment: .bottomLeading
                )
                .overlay(
                    Image(systemName: shot.cameraAngle.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                )

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(.red.opacity(0.8)))
            }
            .offset(x: -4, y: -4)
        }
    }
}

// MARK: - Waiting Panel

struct WaitingPanel: View {
    let message: String
    let subtext: String

    var body: some View {
        GlassPanel {
            HStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(message.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(subtext)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
            }
        }
    }
}

// MARK: - Review Panel

struct ReviewPanel: View {
    @ObservedObject var store: FilmDirectorStore

    var body: some View {
        GlassPanel {
            VStack(spacing: 14) {
                PanelTitle("FILM READY")

                HStack(spacing: 10) {
                    DirectorButton(label: "PLAY", icon: "play.fill", style: .primary) {
                        // Open video player with store.session.latestReadyClip?.videoURL
                    }
                    DirectorButton(label: "MORE SHOTS", icon: "camera.aperture", style: .secondary) {
                        store.dispatch(.enterShotMode)
                    }
                    DirectorButton(label: "RESET", icon: "arrow.counterclockwise", style: .ghost) {
                        store.dispatch(.reset)
                    }
                }
            }
        }
    }
}

// MARK: - Notification Toast

struct NotificationToast: View {
    let notification: DirectorNotification

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notification.icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
            Text(notification.message)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(.black.opacity(0.75))
                .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
        )
    }
}

// MARK: - Shared Design Components

struct GlassPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.black.opacity(0.65))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.09), lineWidth: 0.5))
            )
    }
}

struct PanelTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(3)
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ButtonStyle2 { case primary, secondary, ghost }

struct DirectorButton: View {
    let label: String
    let icon: String
    let style: ButtonStyle2
    let action: () -> Void

    var bg: Color {
        switch style {
        case .primary:   return .white
        case .secondary: return .white.opacity(0.1)
        case .ghost:     return .clear
        }
    }

    var fg: Color {
        switch style {
        case .primary: return .black
        default:       return .white
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(bg)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.1), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }
}

struct DarkTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1), lineWidth: 0.5))
            )
    }
}

extension UIImage {
    func scaledTo(maxDimension: CGFloat) -> UIImage {
        let sourceSize = size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return self }

        let longest = max(sourceSize.width, sourceSize.height)
        guard longest > maxDimension else { return self }

        let scale = maxDimension / longest
        let targetSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

// MARK: - AR Placeholder (replace with ARViewContainer)

struct ARPlaceholderView: View {
    var body: some View {
        ZStack {
            Color.black
            // Dark fantasy gradient bg for preview
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.02, blue: 0.08), Color(red: 0.1, green: 0.05, blue: 0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text("[ AR CAMERA ]")
                .font(.system(size: 12, design: .monospaced))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.1))
        }
    }
}

// MARK: - Preview

#Preview {
    DirectorView()
        .preferredColorScheme(.dark)
}
