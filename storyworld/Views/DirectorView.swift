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
        case .hero: return "OBJECT A"
        case .villain: return "OBJECT B"
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

enum CharacterCreationOption: String, CaseIterable, Identifiable {
    case soldier
    case monster
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soldier: return "SOLDIER"
        case .monster: return "MONSTER"
        case .custom: return "CUSTOM"
        }
    }

    var icon: String {
        switch self {
        case .soldier: return "shield.fill"
        case .monster: return "flame.fill"
        case .custom: return "sparkles"
        }
    }

    var presetPrompt: String? {
        switch self {
        case .soldier:
            return "dark soldier in obsidian armor"
        case .monster:
            return "fire demon with molten skin and curved horns"
        case .custom:
            return nil
        }
    }
}

enum WorldPreset: String, CaseIterable, Identifiable {
    case dirt = "rock_face_03_diff_2k"
    case snow = "snow_02_diff_2k"
    case pavement = "pavement"

    var id: String { rawValue }

    static let sharedSkyboxResourceName = "dry_grass_2k"

    var title: String {
        switch self {
        case .dirt: return "DIRT"
        case .snow: return "SNOW"
        case .pavement: return "PAVEMENT"
        }
    }

    var icon: String {
        switch self {
        case .dirt: return "leaf.fill"
        case .snow: return "snowflake"
        case .pavement: return "square.grid.3x3.fill"
        }
    }

    var floorTextureResourceName: String { rawValue }

    var environmentPrompt: String {
        "epic fantasy environment"
    }
}

// MARK: - Root View

struct DirectorView: View {
    let onExit: (() -> Void)?
    @StateObject private var store: FilmDirectorStore
    @State private var arManager = ARSessionManager()
    @State private var baseEntities: [CharacterSlot: ModelEntity] = [:]
    @State private var currentPlacementSlot: CharacterSlot?
    @State private var placementStatusMessage = ""
    @State private var scaleValue: Double = 1.0
    @State private var hasSurface = false
    @State private var showingGallery = false
    @State private var activeTransformTarget: TransformControlTarget?
    @State private var worldPlaneOffset: Double = -0.22
    @State private var selectedWorldPreset: WorldPreset?
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
                        Slider(value: $scaleValue, in: 0.05...3.0)
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
                selectedWorldPreset: $selectedWorldPreset,
                worldOffset: $worldPlaneOffset,
                placementSlot: currentPlacementSlot,
                statusMessage: placementStatusMessage,
                onCaptureShot: captureShot,
                onCapturePhoto: capturePhoto,
                onPlaceCharacter: handlePlacementTap,
                onSetWorld: setWorld,
                worldStatus: store.session.environment?.status ?? .idle,
                onWorldOffsetChanged: { arManager.setWorldPlaneYOffset(Float($0)) },
                onRemoveWorld: removeWorld,
                onOpenWorldSettings: { worldPlaneOffset = Double(arManager.worldPlaneYOffsetValue) },
                onOpenGallery: { showingGallery = true },
                onExitDirector: exitDirectorMode,
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
                    onSelectWorldPreset: setWorld,
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
            return store.session.hero?.name ?? "Object A"
        case .villain:
            return store.session.villain?.name ?? "Object B"
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
                    if url.lastPathComponent.hasPrefix(devSampleTextTo3DDownloadedFilenamePrefix) {
                        let xAxisFix = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
                        let zAxisFix = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
                        let extraXAxisFix = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
                        loaded.orientation = simd_mul(extraXAxisFix, simd_mul(zAxisFix, simd_mul(xAxisFix, loaded.orientation)))
                    }
                    loaded.generateCollisionShapes(recursive: true)
                    baseEntities[slot] = loaded
                    sourceEntity = loaded
                }

                arManager.stopPreview()
                arManager.startPreview(with: sourceEntity)
                placementStatusMessage = "Position preview, then press PLACE \(slot == .hero ? "OBJECT A" : "OBJECT B")"
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

    private func setWorld(using preset: WorldPreset) {
        selectedWorldPreset = preset
        arManager.setWorldFloorTexture(resourceName: preset.floorTextureResourceName)
        let worldStatus = store.session.environment?.status
        let shouldGenerateWorld = worldStatus != .generating && worldStatus != .ready && worldStatus != .placed
        guard shouldGenerateWorld else { return }

        store.dispatch(
            .setEnvironment(
                prompt: preset.environmentPrompt,
                localSkyboxResourceName: WorldPreset.sharedSkyboxResourceName
            )
        )
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
    @Binding var selectedWorldPreset: WorldPreset?
    @Binding var worldOffset: Double
    let placementSlot: CharacterSlot?
    let statusMessage: String
    let onCaptureShot: (CameraAngle) -> Void
    let onCapturePhoto: () -> Void
    let onPlaceCharacter: () -> Void
    let onSetWorld: (WorldPreset) -> Void
    let worldStatus: GenerationStatus
    let onWorldOffsetChanged: (Double) -> Void
    let onRemoveWorld: () -> Void
    let onOpenWorldSettings: () -> Void
    let onOpenGallery: () -> Void
    let onExitDirector: () -> Void
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
                    selectedWorldPreset: $selectedWorldPreset,
                    worldOffset: $worldOffset,
                    placementSlot: placementSlot,
                    onCaptureShot: onCaptureShot,
                    onCapturePhoto: onCapturePhoto,
                    onPlaceCharacter: onPlaceCharacter,
                    onSetWorld: onSetWorld,
                    worldStatus: worldStatus,
                    onWorldOffsetChanged: onWorldOffsetChanged,
                    onRemoveWorld: onRemoveWorld,
                    onOpenWorldSettings: onOpenWorldSettings
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
    let onTapHero: () -> Void
    let onTapVillain: () -> Void

    var body: some View {
        HStack(spacing: 8) {
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
    @Binding var selectedWorldPreset: WorldPreset?
    @Binding var characterScale: Double
    @Binding var characterYaw: Double
    let hasSurface: Bool
    let worldStatus: GenerationStatus
    let onDismiss: () -> Void
    let onWorldOffsetChanged: (Double) -> Void
    let onSelectWorldPreset: (WorldPreset) -> Void
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
                        Text("FLOOR TYPE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.7))

                        HStack(spacing: 8) {
                            ForEach(WorldPreset.allCases) { preset in
                                let isSelected = preset == selectedWorldPreset
                                Button {
                                    selectedWorldPreset = preset
                                    onSelectWorldPreset(preset)
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
                        Slider(value: $characterScale, in: 0.05...3.0, step: 0.01)
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
    @Binding var selectedWorldPreset: WorldPreset?
    @Binding var worldOffset: Double
    let placementSlot: CharacterSlot?
    let onCaptureShot: (CameraAngle) -> Void
    let onCapturePhoto: () -> Void
    let onPlaceCharacter: () -> Void
    let onSetWorld: (WorldPreset) -> Void
    let worldStatus: GenerationStatus
    let onWorldOffsetChanged: (Double) -> Void
    let onRemoveWorld: () -> Void
    let onOpenWorldSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            switch store.session.phase {

            case .idle:
                IdlePanel(
                    store: store,
                    hasSurface: hasSurface,
                    selectedWorldPreset: $selectedWorldPreset,
                    worldOffset: $worldOffset,
                    onCapturePhoto: onCapturePhoto,
                    onSetWorld: onSetWorld,
                    worldStatus: worldStatus,
                    onWorldOffsetChanged: onWorldOffsetChanged,
                    onRemoveWorld: onRemoveWorld,
                    onOpenWorldSettings: onOpenWorldSettings
                )

            case .generatingWorld:
                WaitingPanel(message: "Summoning the environment...", subtext: "Walk around to explore")

            case .placingWorld:
                IdlePanel(
                    store: store,
                    hasSurface: hasSurface,
                    selectedWorldPreset: $selectedWorldPreset,
                    worldOffset: $worldOffset,
                    onCapturePhoto: onCapturePhoto,
                    onSetWorld: onSetWorld,
                    worldStatus: worldStatus,
                    onWorldOffsetChanged: onWorldOffsetChanged,
                    onRemoveWorld: onRemoveWorld,
                    onOpenWorldSettings: onOpenWorldSettings
                )

            case .generatingCharacter:
                GeneratingCharacterPanel(store: store)

            case .placingCharacters:
                PlacingCharactersPanel(
                    store: store,
                    currentSlot: placementSlot,
                    hasSurface: hasSurface,
                    onPlaceCharacter: onPlaceCharacter,
                    onCapturePhoto: onCapturePhoto
                )

            case .takingShots:
                IdlePanel(
                    store: store,
                    hasSurface: hasSurface,
                    selectedWorldPreset: $selectedWorldPreset,
                    worldOffset: $worldOffset,
                    onCapturePhoto: onCapturePhoto,
                    onSetWorld: onSetWorld,
                    worldStatus: worldStatus,
                    onWorldOffsetChanged: onWorldOffsetChanged,
                    onRemoveWorld: onRemoveWorld,
                    onOpenWorldSettings: onOpenWorldSettings
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
    @Binding var selectedWorldPreset: WorldPreset?
    @Binding var worldOffset: Double
    let onCapturePhoto: () -> Void
    let onSetWorld: (WorldPreset) -> Void
    let worldStatus: GenerationStatus
    let onWorldOffsetChanged: (Double) -> Void
    let onRemoveWorld: () -> Void
    let onOpenWorldSettings: () -> Void
    @State private var showingWorldPicker = false
    @State private var showingCharacterPicker = false
    @State private var selectedCharacterOption: CharacterCreationOption = .soldier
    @State private var customCharacterPrompt = ""
    @State private var voiceService = VoiceService()
    @State private var isHoldingVoiceInput = false
    @State private var isProcessingVoiceInput = false
    @State private var voiceErrorMessage: String?
    @State private var typingTask: Task<Void, Never>?

    var body: some View {
        let worldDone = worldStatus == .ready || worldStatus == .placed
        let objectAAdded = store.session.hero?.status == .ready || store.session.hero?.status == .placed
        let objectBAdded = store.session.villain?.status == .ready || store.session.villain?.status == .placed
        let worldGenerating = worldStatus == .queued || worldStatus == .generating || store.session.phase == .generatingWorld
        let objectAGenerating = store.session.hero?.status == .queued || store.session.hero?.status == .generating
        let objectBGenerating = store.session.villain?.status == .queued || store.session.villain?.status == .generating
        let characterGenerating = objectAGenerating || objectBGenerating || store.session.phase == .generatingCharacter
        let trimmedPrompt = customCharacterPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let heroSlotUnavailable = objectAAdded || objectAGenerating
        let villainSlotUnavailable = objectBAdded || objectBGenerating
        let nextSlot: CharacterSlot? = {
            if !heroSlotUnavailable { return .hero }
            if !villainSlotUnavailable { return .villain }
            return nil
        }()
        let canSubmitDraft = selectedCharacterOption == .custom ? !trimmedPrompt.isEmpty : true
        let addButtonLabel = "ADD TO SCENE"

        GlassPanel {
            if showingWorldPicker {
                VStack(spacing: 10) {
                    PanelTitle("WORLD")

                    HStack(spacing: 8) {
                        ForEach(WorldPreset.allCases) { preset in
                            let selected = selectedWorldPreset == preset
                            Button {
                                selectedWorldPreset = preset
                                onSetWorld(preset)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: preset.icon)
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(preset.title)
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .tracking(1)
                                }
                                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.85))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selected ? Color.white : Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(.white.opacity(selected ? 0.0 : 0.14), lineWidth: 0.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(worldGenerating)
                        }
                    }
                    .animation(nil, value: selectedWorldPreset)

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

                    if worldDone {
                        DirectorButton(
                            label: "REMOVE WORLD",
                            icon: "trash",
                            style: .ghost,
                            action: onRemoveWorld
                        )
                    }

                    DirectorButton(label: "BACK", icon: "arrow.left", style: .ghost) {
                        showingWorldPicker = false
                    }
                }
            } else if showingCharacterPicker {
                VStack(spacing: 10) {
                    PanelTitle("ADD CHARACTER")

                    HStack(spacing: 8) {
                        ForEach(CharacterCreationOption.allCases) { option in
                            let selected = selectedCharacterOption == option
                            Button {
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    selectedCharacterOption = option
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: option.icon)
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(option.title)
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .tracking(1)
                                }
                                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.85))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selected ? Color.white : Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(.white.opacity(selected ? 0.0 : 0.14), lineWidth: 0.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .animation(nil, value: selectedCharacterOption)

                    if selectedCharacterOption == .custom {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("LOOK / STYLE PROMPT")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .tracking(1)
                                    .foregroundStyle(.white.opacity(0.7))
                                Spacer()
                                if !trimmedPrompt.isEmpty {
                                    ClearPromptButton {
                                        clearCustomCharacterPrompt()
                                    }
                                }
                                HoldToTalkButton(
                                    isHolding: isHoldingVoiceInput,
                                    isProcessing: isProcessingVoiceInput,
                                    onPress: startVoiceCaptureForCustomCharacter,
                                    onRelease: finishVoiceCaptureForCustomCharacter
                                )
                            }

                            TextEditor(text: $customCharacterPrompt)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 84, maxHeight: 120)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.white.opacity(0.06))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1), lineWidth: 0.5))
                                )

                            Text(customCharacterVoiceStatusText)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(customCharacterVoiceStatusColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                        }
                    }

                    DirectorButton(
                        label: addButtonLabel,
                        icon: selectedCharacterOption.icon,
                        style: .primary
                    ) {
                        guard let slot = nextSlot else { return }
                        let basePrompt = selectedCharacterOption.presetPrompt ?? trimmedPrompt
                        let prompt = selectedCharacterOption == .custom
                            ? "\(devSampleTextTo3DMarker) \(basePrompt)"
                            : basePrompt
                        switch slot {
                        case .hero:
                            store.dispatch(.generateHero(name: nil, prompt: prompt))
                        case .villain:
                            store.dispatch(.generateVillain(name: nil, prompt: prompt))
                        }
                        customCharacterPrompt = ""
                        resetCustomCharacterVoiceInput()
                        showingCharacterPicker = false
                    }
                    .disabled(worldGenerating || nextSlot == nil || !canSubmitDraft)

                    if nextSlot == nil {
                        Text("Both object slots are already in use.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !canSubmitDraft {
                        Text("Add a style prompt to generate your model.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    DirectorButton(label: "BACK", icon: "arrow.left", style: .ghost) {
                        customCharacterPrompt = ""
                        resetCustomCharacterVoiceInput()
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
                        DirectorButton(label: "WORLD", icon: "globe.europe.africa.fill", style: .secondary) {
                            onOpenWorldSettings()
                            showingWorldPicker = true
                        }

                        DirectorButton(label: "ADD CHARACTER", icon: "person.2.fill", style: .secondary) {
                            showingCharacterPicker = true
                        }
                        .disabled(
                            worldGenerating
                            || nextSlot == nil
                        )
                    }

                    if worldGenerating || characterGenerating {
                        Text(worldGenerating ? "Setting world..." : "Adding character...")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    if store.session.canShoot {
                        DirectorButton(label: "TAKE PHOTO", icon: "camera.fill", style: .primary, action: onCapturePhoto)
                    }
                }
            }
        }
        .onChange(of: selectedCharacterOption) { _, option in
            if option != .custom {
                resetCustomCharacterVoiceInput()
            }
        }
        .onChange(of: showingCharacterPicker) { _, isShowing in
            if !isShowing {
                resetCustomCharacterVoiceInput()
            }
        }
        .onDisappear {
            resetCustomCharacterVoiceInput()
        }
    }

    private func startVoiceCaptureForCustomCharacter() {
        guard
            showingCharacterPicker,
            selectedCharacterOption == .custom,
            !isHoldingVoiceInput,
            !isProcessingVoiceInput
        else { return }

        voiceErrorMessage = nil
        voiceService.startListening()
        if voiceService.isListening {
            isHoldingVoiceInput = true
        } else {
            voiceErrorMessage = "Microphone unavailable"
        }
    }

    private func finishVoiceCaptureForCustomCharacter() {
        guard isHoldingVoiceInput else { return }
        isHoldingVoiceInput = false
        isProcessingVoiceInput = true

        Task {
            let transcription = await voiceService.stopListeningAndTranscribe()?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            await MainActor.run {
                isProcessingVoiceInput = false
                if let transcription, !transcription.isEmpty {
                    appendCustomPromptWithTypingAnimation(transcription)
                } else {
                    voiceErrorMessage = "No speech detected"
                }
            }
        }
    }

    private func appendCustomPromptWithTypingAnimation(_ text: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return }

        let spacing = customCharacterPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " "
        let appendedText = spacing + normalizedText
        voiceErrorMessage = nil

        typingTask?.cancel()
        typingTask = Task {
            for character in appendedText {
                if Task.isCancelled { return }
                await MainActor.run {
                    customCharacterPrompt.append(character)
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func clearCustomCharacterPrompt() {
        customCharacterPrompt = ""
        resetCustomCharacterVoiceInput()
    }

    private func resetCustomCharacterVoiceInput() {
        if voiceService.isListening {
            voiceService.cancelListening()
        }
        isHoldingVoiceInput = false
        isProcessingVoiceInput = false
        voiceErrorMessage = nil
        typingTask?.cancel()
        typingTask = nil
    }

    private var customCharacterVoiceStatusText: String {
        if isHoldingVoiceInput { return "Listening... release to insert" }
        if isProcessingVoiceInput { return "Transcribing..." }
        if let voiceErrorMessage { return voiceErrorMessage }
        return "-"
    }

    private var customCharacterVoiceStatusColor: Color {
        if isHoldingVoiceInput { return .green }
        if isProcessingVoiceInput { return .white.opacity(0.65) }
        if voiceErrorMessage != nil { return .orange }
        return .white.opacity(0.3)
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
    @ObservedObject var store: FilmDirectorStore

    var body: some View {
        GlassPanel {
            VStack(spacing: 14) {
                PanelTitle("SUMMONING")
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.9)
                    .tint(.orange)
                DirectorButton(label: "PLACE NOW", icon: "plus.viewfinder", style: .primary) {
                    store.dispatch(.enterShotMode)
                }
            }
        }
    }
}

// MARK: - Placing Characters Panel

struct PlacingCharactersPanel: View {
    @ObservedObject var store: FilmDirectorStore
    let currentSlot: CharacterSlot?
    let hasSurface: Bool
    let onPlaceCharacter: () -> Void
    let onCapturePhoto: () -> Void

    private var slotLabel: String {
        switch currentSlot {
        case .hero: return "OBJECT A"
        case .villain: return "OBJECT B"
        case .none: return "OBJECT"
        }
    }

    var body: some View {
        GlassPanel {
            VStack(spacing: 14) {
                PanelTitle("PLACE CHARACTERS")
                Text("Position the highlighted preview, then place it into the scene.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Drag to rotate preview. Use right slider to scale.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))

                DirectorButton(
                    label: "PLACE \(slotLabel)",
                    icon: "plus.viewfinder",
                    style: .primary,
                    action: onPlaceCharacter
                )
                .disabled(currentSlot == nil || !hasSurface)

                if store.session.canShoot {
                    DirectorButton(label: "TAKE PHOTO", icon: "camera.fill", style: .primary, action: onCapturePhoto)
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
    @State private var voiceService = VoiceService()
    @State private var isHoldingVoiceInput = false
    @State private var isProcessingVoiceInput = false
    @State private var voiceErrorMessage: String?
    @State private var typingTask: Task<Void, Never>?

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

    private var hasAnimatePromptContent: Bool {
        !animatePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    resetVoiceInput()
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
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    DarkTextField(placeholder: "Describe motion...", text: $animatePrompt)
                                    HoldToTalkButton(
                                        isHolding: isHoldingVoiceInput,
                                        isProcessing: isProcessingVoiceInput,
                                        onPress: startVoiceCapture,
                                        onRelease: finishVoiceCapture
                                    )
                                    if hasAnimatePromptContent {
                                        ClearPromptButton {
                                            clearAnimatePrompt()
                                        }
                                    }
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

                                if isHoldingVoiceInput {
                                    Text("Listening... release to insert")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.green)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else if isProcessingVoiceInput {
                                    Text("Transcribing...")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.65))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else if let voiceErrorMessage {
                                    Text(voiceErrorMessage)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.orange)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
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
        .onDisappear {
            resetVoiceInput()
        }
    }

    private func clearAnimatePrompt() {
        animatePrompt = ""
        resetVoiceInput()
    }

    private func submitAnimatePrompt() {
        guard let photoId = selectedPhotoId else { return }
        let trimmedPrompt = animatePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }
        onAnimatePhoto(photoId, trimmedPrompt)
        animatePrompt = ""
        showingAnimatePrompt = false
        resetVoiceInput()
    }

    private func startVoiceCapture() {
        guard showingAnimatePrompt, !isHoldingVoiceInput, !isProcessingVoiceInput else { return }
        voiceErrorMessage = nil
        voiceService.startListening()
        if voiceService.isListening {
            isHoldingVoiceInput = true
        } else {
            voiceErrorMessage = "Microphone unavailable"
        }
    }

    private func finishVoiceCapture() {
        guard isHoldingVoiceInput else { return }
        isHoldingVoiceInput = false
        isProcessingVoiceInput = true

        Task {
            let transcription = await voiceService.stopListeningAndTranscribe()?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            await MainActor.run {
                isProcessingVoiceInput = false
                if let transcription, !transcription.isEmpty {
                    appendPromptWithTypingAnimation(transcription)
                } else {
                    voiceErrorMessage = "No speech detected"
                }
            }
        }
    }

    private func appendPromptWithTypingAnimation(_ text: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return }

        let spacing = animatePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " "
        let appendedText = spacing + normalizedText
        voiceErrorMessage = nil

        typingTask?.cancel()
        typingTask = Task {
            for character in appendedText {
                if Task.isCancelled { return }
                await MainActor.run {
                    animatePrompt.append(character)
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func resetVoiceInput() {
        if voiceService.isListening {
            voiceService.cancelListening()
        }
        isHoldingVoiceInput = false
        isProcessingVoiceInput = false
        voiceErrorMessage = nil
        typingTask?.cancel()
        typingTask = nil
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
    @State private var isExpanded = false

    private var isErrorNotification: Bool {
        notification.icon == "exclamationmark.triangle" ||
        notification.message.contains("⚠️") ||
        notification.message.localizedCaseInsensitiveContains("failed")
    }

    private var shouldClamp: Bool {
        isErrorNotification && !isExpanded
    }

    private let toastMaxWidth: CGFloat = 320

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notification.icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
            Text(notification.message)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(shouldClamp ? 1 : nil)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
            if isErrorNotification {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: toastMaxWidth, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.75))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 0.5))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard isErrorNotification else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
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

struct HoldToTalkButton: View {
    let isHolding: Bool
    let isProcessing: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isProcessing ? "waveform" : "mic.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(labelText)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHolding ? Color.red.opacity(0.78) : Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isHolding ? .red.opacity(0.35) : .white.opacity(0.14), lineWidth: 0.6)
                )
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    onPress()
                }
                .onEnded { _ in
                    onRelease()
                }
        )
        .opacity(isProcessing ? 0.72 : 1.0)
    }

    private var labelText: String {
        if isProcessing { return "WAIT" }
        if isHolding { return "RELEASE" }
        return "HOLD"
    }
}

struct ClearPromptButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("CLEAR")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.6)
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.14), lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
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
