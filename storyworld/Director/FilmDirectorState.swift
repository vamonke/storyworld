import SwiftUI
import RealityKit
import ARKit
import Combine

// MARK: - ProductionPhase

enum ProductionPhase: String, Codable, CaseIterable {
    case idle
    case generatingWorld
    case placingWorld
    case generatingCharacter
    case placingCharacters
    case takingShots
    case generatingClip
    case reviewingClip

    var displayName: String {
        switch self {
        case .idle:                return "Ready"
        case .generatingWorld:     return "Summoning World..."
        case .placingWorld:        return "Place World"
        case .generatingCharacter: return "Summoning Character..."
        case .placingCharacters:   return "Place Characters"
        case .takingShots:         return "Director Mode"
        case .generatingClip:      return "Rendering Film..."
        case .reviewingClip:       return "Film Ready"
        }
    }

    var icon: String {
        switch self {
        case .idle:                return "wand.and.stars"
        case .generatingWorld:     return "globe.europe.africa.fill"
        case .placingWorld:        return "arrow.down.to.line"
        case .generatingCharacter: return "cube.transparent"
        case .placingCharacters:   return "plus.viewfinder"
        case .takingShots:         return "camera.aperture"
        case .generatingClip:      return "film.stack"
        case .reviewingClip:       return "play.rectangle.fill"
        }
    }
}

// MARK: - Supporting Enums

enum CharacterSlot: String, Codable, CaseIterable {
    case hero    // knight — always slot 1
    case villain // monster — always slot 2
}

enum GenerationStatus: String, Codable {
    case idle, queued, generating, ready, placed, failed
}

enum CameraAngle: String, Codable, CaseIterable {
    case wideEstablishing
    case mediumTwoShot
    case mediumSingle
    case closeUpFace
    case overTheShoulder
    case lowAngleHeroic
    case insertDetail

    var displayName: String {
        switch self {
        case .wideEstablishing: return "Wide"
        case .mediumTwoShot:    return "Two Shot"
        case .mediumSingle:     return "Medium"
        case .closeUpFace:      return "Close Up"
        case .overTheShoulder:  return "OTS"
        case .lowAngleHeroic:   return "Low Angle"
        case .insertDetail:     return "Insert"
        }
    }

    var icon: String {
        switch self {
        case .wideEstablishing: return "arrow.up.left.and.arrow.down.right"
        case .mediumTwoShot:    return "person.2"
        case .mediumSingle:     return "person"
        case .closeUpFace:      return "eyes"
        case .overTheShoulder:  return "figure.walk"
        case .lowAngleHeroic:   return "arrow.up"
        case .insertDetail:     return "magnifyingglass"
        }
    }

    var defaultDuration: Double {
        switch self {
        case .wideEstablishing: return 3.0
        case .closeUpFace:      return 2.0
        case .insertDetail:     return 1.5
        default:                return 2.5
        }
    }
}

enum CinematicStyle: String, Codable, CaseIterable {
    case epicFantasy
    case darkGritty
    case animeAction
    case mythologicalDrama

    var displayName: String {
        switch self {
        case .epicFantasy:        return "Epic Fantasy"
        case .darkGritty:         return "Dark & Gritty"
        case .animeAction:        return "Anime Action"
        case .mythologicalDrama:  return "Mythological Drama"
        }
    }

    var audioPrompt: String {
        switch self {
        case .epicFantasy:
            return "epic orchestral score, choir, timpani, hero theme, sweeping strings, battle drums"
        case .darkGritty:
            return "dark ambient, heavy percussion, dissonant strings, low brass, ominous tension"
        case .animeAction:
            return "fast-paced anime battle music, electric guitar, dramatic build, intense percussion"
        case .mythologicalDrama:
            return "ancient mythological score, world percussion, haunting vocals, epic brass"
        }
    }
}

// MARK: - Models

struct ARCharacter: Identifiable, Codable {
    let id: UUID
    let slot: CharacterSlot
    var name: String
    var voicePrompt: String
    var generationPrompt: String
    var status: GenerationStatus
    var modelURL: URL?
    var thumbnailURL: URL?
    var rodinJobId: String?
    var tags: [String]
    var createdAt: Date

    // Not codable — runtime only
    var anchorIdentifier: UUID?

    static func hero(prompt: String) -> ARCharacter {
        ARCharacter(
            id: UUID(),
            slot: .hero,
            name: "Knight",
            voicePrompt: prompt,
            generationPrompt: "",
            status: .queued,
            tags: [],
            createdAt: Date()
        )
    }

    static func villain(prompt: String) -> ARCharacter {
        ARCharacter(
            id: UUID(),
            slot: .villain,
            name: "Monster",
            voicePrompt: prompt,
            generationPrompt: "",
            status: .queued,
            tags: [],
            createdAt: Date()
        )
    }
}

struct AREnvironment: Codable {
    var voicePrompt: String
    var generationPrompt: String
    var status: GenerationStatus
    var panoramaURL: URL?
    var skyboxJobId: String?
}

struct ARShot: Identifiable, Codable {
    let id: UUID
    var index: Int
    var frameImageData: Data          // UIImage as PNG data
    var cinematicFrameImageData: Data?
    var cameraAngle: CameraAngle
    var description: String
    var klingPrompt: String           // per-shot Kling prompt, expanded by GPT-5
    var duration: Double
    var capturedAt: Date
    var characterSlots: [CharacterSlot] // which characters are in frame

    var frameImage: UIImage? {
        UIImage(data: cinematicFrameImageData ?? frameImageData)
    }
}

struct ARClip: Identifiable, Codable {
    let id: UUID
    var shotIds: [UUID]               // ordered
    var status: GenerationStatus
    var klingJobId: String?
    var videoURL: URL?
    var duration: Double
    var cinematicStyle: CinematicStyle
    var audioPrompt: String
    var generatedAt: Date?
}

enum MemoryPhotoProcessingStatus: String, Codable {
    case processing
    case ready
    case failed
}

struct ARMemoryPhoto: Identifiable, Codable {
    let id: UUID
    var imageData: Data
    var capturedAt: Date
    var processingStatus: MemoryPhotoProcessingStatus
    var processingError: String?

    var image: UIImage? {
        UIImage(data: imageData)
    }
}

struct ARMemoryVideo: Identifiable, Codable {
    let id: UUID
    var sourcePhotoId: UUID
    var prompt: String
    var thumbnailImageData: Data
    var capturedAt: Date
    var processingStatus: MemoryPhotoProcessingStatus
    var processingError: String?
    var videoURL: URL?

    var thumbnailImage: UIImage? {
        UIImage(data: thumbnailImageData)
    }
}

// MARK: - Full Session State

struct FilmSession: Codable {
    var phase: ProductionPhase = .idle

    // Max 2 characters
    var hero: ARCharacter?            // slot: .hero
    var villain: ARCharacter?         // slot: .villain

    var environment: AREnvironment?

    var shots: [ARShot] = []          // ordered by capture time
    var clips: [ARClip] = []          // can have multiple clips
    var photos: [ARMemoryPhoto] = []  // in-memory gallery
    var videos: [ARMemoryVideo] = []  // in-memory gallery

    // Derived
    var allCharacters: [ARCharacter] {
        [hero, villain].compactMap { $0 }
    }

    var placedCharacters: [ARCharacter] {
        allCharacters.filter { $0.status == .placed }
    }

    var heroReady: Bool   { hero?.status == .ready || hero?.status == .placed }
    var villainReady: Bool { villain?.status == .ready || villain?.status == .placed }
    var bothPlaced: Bool  { hero?.status == .placed && villain?.status == .placed }
    var envReady: Bool    { environment?.status == .ready }
    // Allow freestyle capture even before world/characters are prepared.
    var canShoot: Bool    { true }
    var canGenerate: Bool { shots.count >= 3 }
    var hasPhotos: Bool   { !photos.isEmpty }
    var processingPhotosCount: Int { processingMediaCount }
    var failedPhotosCount: Int { failedMediaCount }
    var hasMedia: Bool { !photos.isEmpty || !videos.isEmpty }
    var processingMediaCount: Int {
        photos.filter { $0.processingStatus == .processing }.count
        + videos.filter { $0.processingStatus == .processing }.count
    }
    var failedMediaCount: Int {
        photos.filter { $0.processingStatus == .failed }.count
        + videos.filter { $0.processingStatus == .failed }.count
    }

    var activeClip: ARClip? { clips.last }
    var latestReadyClip: ARClip? { clips.last(where: { $0.status == .ready }) }

    static var empty: FilmSession { FilmSession() }
}

// MARK: - Actions

enum DirectorAction {
    // World
    case setEnvironment(prompt: String, localSkyboxResourceName: String?)

    // Characters
    case generateHero(prompt: String)
    case generateVillain(prompt: String)

    // Background completions (fired by pollers)
    case environmentReady(panoramaURL: URL)
    case heroReady(modelURL: URL)
    case villainReady(modelURL: URL)
    case generationFailed(slot: CharacterSlot?, error: String)

    // Placement (AR tap)
    case placeHero(anchorId: UUID)
    case placeVillain(anchorId: UUID)

    // Shots
    case captureShot(angle: CameraAngle, image: UIImage, charactersInFrame: [CharacterSlot])
    case shotCinematicReady(id: UUID, imageData: Data)
    case shotCinematicFailed(id: UUID, error: String)
    case deleteShot(id: UUID)
    case reorderShots(fromIndex: Int, toIndex: Int)
    case captureMemoryPhoto(image: UIImage)
    case memoryPhotoCinematicReady(id: UUID, imageData: Data)
    case memoryPhotoCinematicFailed(id: UUID, error: String)
    case animateMemoryPhoto(id: UUID, prompt: String)
    case memoryVideoReady(id: UUID, videoURL: URL)
    case memoryVideoFailed(id: UUID, error: String)
    case deleteMemoryPhoto(id: UUID)
    case deleteMemoryVideo(id: UUID)

    // Clip generation
    case generateClip(shotIds: [UUID], style: CinematicStyle)
    case clipReady(id: UUID, videoURL: URL)
    case clipFailed(id: UUID, error: String)

    // Navigation
    case enterShotMode
    case exitShotMode
    case clearEnvironment
    case clearCharacter(slot: CharacterSlot)
    case reset
}

// MARK: - Notification

struct DirectorNotification: Identifiable {
    let id = UUID()
    let message: String
    let icon: String
    let createdAt = Date()
}

// MARK: - Store

@MainActor
final class FilmDirectorStore: ObservableObject {

    @Published var session: FilmSession = .empty
    @Published var notifications: [DirectorNotification] = []

    // Injected services (swap for mocks in previews/tests)
    var generationService: GenerationServiceProtocol
    var arScene: ARSceneProtocol

    private var cancellables = Set<AnyCancellable>()
    private var hasShownCinematicFailure = false
    private var hasSeededDefaultGalleryPhoto = false

    init(
        generationService: GenerationServiceProtocol = MockGenerationService(),
        arScene: ARSceneProtocol = NoopARScene.shared
    ) {
        self.generationService = generationService
        self.arScene = arScene

        Task { [weak self] in
            await self?.seedDefaultGalleryPhotoIfNeeded()
        }
    }

    // MARK: - Single dispatch entry point

    func dispatch(_ action: DirectorAction) {
        switch action {

        // MARK: World

        case .setEnvironment(let prompt, let localSkyboxResourceName):
            if session.environment?.status == .generating || session.environment?.status == .ready || session.environment?.status == .placed {
                notify("World already set", icon: "checkmark.circle")
                return
            }
            let env = AREnvironment(
                voicePrompt: prompt,
                generationPrompt: PromptExpander.environment(prompt),
                status: .generating
            )
            session.environment = env
            session.phase = .generatingWorld

            if let localSkyboxResourceName,
               let localSkyboxURL = Bundle.main.url(forResource: localSkyboxResourceName, withExtension: "hdr") {
                session.environment?.panoramaURL = localSkyboxURL
                session.environment?.status = .ready
                arScene.applySkybox(localSkyboxURL)
                notify("🌍 Battlefield ready", icon: "globe.europe.africa.fill")
                autoAdvancePhase()
                return
            }

            Task {
                do {
                    let url = try await generationService.generateSkybox(env.generationPrompt)
                    dispatch(.environmentReady(panoramaURL: url))
                } catch {
                    notify("⚠️ World generation failed", icon: "exclamationmark.triangle")
                    session.environment?.status = .failed
                }
            }

        case .environmentReady(let url):
            session.environment?.panoramaURL = url
            session.environment?.status = .ready
            arScene.applySkybox(url)                       // auto-apply, non-blocking
            notify("🌍 Battlefield ready", icon: "globe.europe.africa.fill")

            // AUTO-ADVANCE
            autoAdvancePhase()

        // MARK: Characters

        case .generateHero(let prompt):
            if session.phase == .generatingWorld {
                notify("Finish setting world first", icon: "pause.circle")
                return
            }
            if session.hero?.status == .queued
                || session.hero?.status == .generating
                || session.hero?.status == .ready
                || session.hero?.status == .placed {
                notify("Knight already added", icon: "checkmark.circle")
                return
            }
            var character = ARCharacter.hero(prompt: prompt)
            character.generationPrompt = PromptExpander.character(prompt, slot: .hero)
            session.hero = character
            session.phase = .generatingCharacter

            Task {
                do {
                    let url = try await generationService.generateCharacter(character.generationPrompt)
                    dispatch(.heroReady(modelURL: url))
                } catch {
                    dispatch(.generationFailed(slot: .hero, error: error.localizedDescription))
                }
            }

        case .generateVillain(let prompt):
            if session.phase == .generatingWorld {
                notify("Finish setting world first", icon: "pause.circle")
                return
            }
            if session.villain?.status == .queued
                || session.villain?.status == .generating
                || session.villain?.status == .ready
                || session.villain?.status == .placed {
                notify("Monster already added", icon: "checkmark.circle")
                return
            }
            var character = ARCharacter.villain(prompt: prompt)
            character.generationPrompt = PromptExpander.character(prompt, slot: .villain)
            session.villain = character

            // Don't change phase if already generating hero — both run in parallel
            if session.phase == .idle || session.phase == .placingWorld {
                session.phase = .generatingCharacter
            }

            Task {
                do {
                    let url = try await generationService.generateCharacter(character.generationPrompt)
                    dispatch(.villainReady(modelURL: url))
                } catch {
                    dispatch(.generationFailed(slot: .villain, error: error.localizedDescription))
                }
            }

        case .heroReady(let url):
            let heroURL = Bundle.main.url(forResource: "rex", withExtension: "usdz") ?? url
            session.hero?.modelURL = heroURL
            session.hero?.status = .ready
            notify("⚔️ Knight ready — tap to place", icon: "figure.stand")
            autoAdvancePhase()

        case .villainReady(let url):
            let villainURL = Bundle.main.url(forResource: "spider_creature", withExtension: "usdz") ?? url
            session.villain?.modelURL = villainURL
            session.villain?.status = .ready
            notify("🔥 Monster ready — tap to place", icon: "flame.fill")
            autoAdvancePhase()

        case .generationFailed(let slot, let error):
            if let slot = slot {
                if slot == .hero { session.hero?.status = .failed }
                else { session.villain?.status = .failed }
            }
            notify("⚠️ Generation failed: \(error)", icon: "exclamationmark.triangle")

        // MARK: Placement

        case .placeHero(let anchorId):
            session.hero?.anchorIdentifier = anchorId
            session.hero?.status = .placed
            notify("⚔️ Knight placed", icon: "checkmark.circle.fill")
            autoAdvancePhase()

        case .placeVillain(let anchorId):
            session.villain?.anchorIdentifier = anchorId
            session.villain?.status = .placed
            notify("🔥 Monster placed", icon: "checkmark.circle.fill")
            autoAdvancePhase()

        // MARK: Shots

        case .captureShot(let angle, let image, let characters):
            guard let imageData = image.pngData() else { return }
            let shotIndex = session.shots.count + 1
            let prompt = PromptExpander.shot(
                angle: angle,
                session: session,
                index: shotIndex
            )
            let cinematicPrompt = PromptExpander.cinematicShotEdit(
                angle: angle,
                session: session,
                index: shotIndex
            )
            let shot = ARShot(
                id: UUID(),
                index: shotIndex,
                frameImageData: imageData,
                cinematicFrameImageData: nil,
                cameraAngle: angle,
                description: angle.displayName,
                klingPrompt: prompt,
                duration: angle.defaultDuration,
                capturedAt: Date(),
                characterSlots: characters
            )
            session.shots.append(shot)
            notify("📸 Shot \(shot.index) — \(angle.displayName)", icon: "camera.fill")

            let shotId = shot.id
            Task {
                do {
                    let cinematicData = try await generationService.enhanceShotCinematic(
                        imageData: imageData,
                        prompt: cinematicPrompt
                    )
                    dispatch(.shotCinematicReady(id: shotId, imageData: cinematicData))
                } catch {
                    dispatch(.shotCinematicFailed(id: shotId, error: error.localizedDescription))
                }
            }

        case .shotCinematicReady(let id, let imageData):
            guard let idx = session.shots.firstIndex(where: { $0.id == id }) else { return }
            session.shots[idx].cinematicFrameImageData = imageData

        case .shotCinematicFailed(let id, let error):
            guard session.shots.contains(where: { $0.id == id }) else { return }
            guard !hasShownCinematicFailure else { return }
            notify("⚠️ Cinematic pass failed (\(error)). Using original frame.", icon: "sparkles")
            hasShownCinematicFailure = true

        case .deleteShot(let id):
            session.shots.removeAll { $0.id == id }
            // Re-index
            for i in session.shots.indices {
                session.shots[i].index = i + 1
            }

        case .reorderShots(let from, let to):
            session.shots.move(fromOffsets: IndexSet(integer: from), toOffset: to)
            for i in session.shots.indices {
                session.shots[i].index = i + 1
            }

        case .captureMemoryPhoto(let image):
            guard let imageData = image.jpegData(compressionQuality: 0.78) else { return }
            let photoId = UUID()
            let item = ARMemoryPhoto(
                id: photoId,
                imageData: imageData,
                capturedAt: Date(),
                processingStatus: .processing,
                processingError: nil
            )
            session.photos.insert(item, at: 0)
            notify("📷 Photo saved", icon: "photo")

            Task {
                do {
                    let cinematicData = try await generationService.enhanceShotCinematic(
                        imageData: imageData,
                        prompt: PromptExpander.cinematicMemoryPhotoEdit()
                    )
                    dispatch(.memoryPhotoCinematicReady(id: photoId, imageData: cinematicData))
                } catch {
                    dispatch(.memoryPhotoCinematicFailed(id: photoId, error: error.localizedDescription))
                }
            }

        case .memoryPhotoCinematicReady(let id, let imageData):
            guard let idx = session.photos.firstIndex(where: { $0.id == id }) else { return }
            session.photos[idx].imageData = imageData
            session.photos[idx].processingStatus = .ready
            session.photos[idx].processingError = nil

        case .memoryPhotoCinematicFailed(let id, let error):
            guard let idx = session.photos.firstIndex(where: { $0.id == id }) else { return }
            session.photos[idx].processingStatus = .failed
            session.photos[idx].processingError = error
            notify("⚠️ Photo cinematic failed: \(error)", icon: "exclamationmark.triangle")

        case .animateMemoryPhoto(let id, let prompt):
            guard let photo = session.photos.first(where: { $0.id == id }) else { return }
            let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPrompt.isEmpty else { return }

            let videoId = UUID()
            let video = ARMemoryVideo(
                id: videoId,
                sourcePhotoId: id,
                prompt: trimmedPrompt,
                thumbnailImageData: photo.imageData,
                capturedAt: Date(),
                processingStatus: .processing,
                processingError: nil,
                videoURL: nil
            )
            session.videos.insert(video, at: 0)
            notify("🎞️ Animation queued", icon: "sparkles")

            Task {
                do {
                    let videoURL = try await generationService.animateImageToVideo(
                        imageData: photo.imageData,
                        prompt: trimmedPrompt
                    )
                    dispatch(.memoryVideoReady(id: videoId, videoURL: videoURL))
                } catch {
                    dispatch(.memoryVideoFailed(id: videoId, error: error.localizedDescription))
                }
            }

        case .memoryVideoReady(let id, let videoURL):
            guard let idx = session.videos.firstIndex(where: { $0.id == id }) else { return }
            session.videos[idx].videoURL = videoURL
            session.videos[idx].processingStatus = .ready
            session.videos[idx].processingError = nil
            notify("🎬 Animation ready", icon: "play.rectangle.fill")

        case .memoryVideoFailed(let id, let error):
            guard let idx = session.videos.firstIndex(where: { $0.id == id }) else { return }
            session.videos[idx].processingStatus = .failed
            session.videos[idx].processingError = error
            notify("⚠️ Animation failed: \(error)", icon: "exclamationmark.triangle")

        case .deleteMemoryPhoto(let id):
            session.photos.removeAll { $0.id == id }

        case .deleteMemoryVideo(let id):
            session.videos.removeAll { $0.id == id }

        // MARK: Clip

        case .generateClip(let shotIds, let style):
            let orderedShots = shotIds.compactMap { id in
                session.shots.first { $0.id == id }
            }
            let totalDuration = orderedShots.map(\.duration).reduce(0, +)
            let clip = ARClip(
                id: UUID(),
                shotIds: shotIds,
                status: .generating,
                duration: totalDuration,
                cinematicStyle: style,
                audioPrompt: style.audioPrompt
            )
            session.clips.append(clip)
            session.phase = .generatingClip

            let clipId = clip.id
            Task {
                do {
                    let frames = orderedShots.compactMap { $0.frameImage }
                    let videoURL = try await generationService.generateClip(
                        frames: frames,
                        shots: orderedShots,
                        style: style,
                        audioPrompt: clip.audioPrompt
                    )
                    dispatch(.clipReady(id: clipId, videoURL: videoURL))
                } catch {
                    dispatch(.clipFailed(id: clipId, error: error.localizedDescription))
                }
            }

        case .clipReady(let id, let url):
            if let i = session.clips.firstIndex(where: { $0.id == id }) {
                session.clips[i].videoURL = url
                session.clips[i].status = .ready
                session.clips[i].generatedAt = Date()
            }
            notify("🎬 Film ready — tap to play", icon: "play.rectangle.fill")
            autoAdvancePhase()

        case .clipFailed(let id, let error):
            if let i = session.clips.firstIndex(where: { $0.id == id }) {
                session.clips[i].status = .failed
            }
            notify("⚠️ Render failed: \(error)", icon: "exclamationmark.triangle")
            session.phase = .takingShots

        // MARK: Navigation

        case .enterShotMode:
            if session.canShoot {
                session.phase = .takingShots
            }

        case .exitShotMode:
            session.phase = .idle

        case .clearEnvironment:
            session.environment = nil
            arScene.removeWorld()
            notify("🌫️ World removed", icon: "trash")
            if session.phase == .takingShots {
                session.phase = .idle
            }

        case .clearCharacter(let slot):
            switch slot {
            case .hero:
                session.hero = nil
                notify("⚔️ Knight removed", icon: "trash")
            case .villain:
                session.villain = nil
                notify("🔥 Monster removed", icon: "trash")
            }
            arScene.removeCharacter(slot: slot)
            if session.phase == .takingShots {
                session.phase = .idle
            }

        case .reset:
            session = .empty
            hasShownCinematicFailure = false
            hasSeededDefaultGalleryPhoto = false
            arScene.reset()
            Task { [weak self] in
                await self?.seedDefaultGalleryPhotoIfNeeded()
            }
        }
    }

    // MARK: - Auto-advance logic

    private func autoAdvancePhase() {
        let s = session
        switch s.phase {

        case .generatingWorld:
            if s.envReady {
                session.phase = .idle
            }

        case .placingWorld:
            if s.envReady {
                session.phase = .idle
            }

        case .generatingCharacter:
            if s.heroReady || s.villainReady {
                session.phase = .idle
            }

        case .placingCharacters:
            // Both placed AND env ready → go shoot
            if s.bothPlaced && s.envReady {
                session.phase = .takingShots
            }
            // One placed, env ready → allow shooting but still show place UI for second
            else if s.placedCharacters.count >= 1 && s.envReady {
                session.phase = .takingShots
            }

        case .generatingClip:
            if s.latestReadyClip != nil {
                session.phase = .reviewingClip
            }

        default:
            break
        }
    }

    // MARK: - Helpers

    private func notify(_ message: String, icon: String) {
        let n = DirectorNotification(message: message, icon: icon)
        notifications.append(n)
        // Auto-dismiss after 4s
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            notifications.removeAll { $0.id == n.id }
        }
    }

    private func seedDefaultGalleryPhotoIfNeeded() async {
        guard !hasSeededDefaultGalleryPhoto else { return }
        hasSeededDefaultGalleryPhoto = true

        guard let imageData = loadDefaultCatImageData() else {
            notify("⚠️ Default gallery photo not found (cat.jpg)", icon: "exclamationmark.triangle")
            return
        }

        let photoId = UUID()
        let photo = ARMemoryPhoto(
            id: photoId,
            imageData: imageData,
            capturedAt: Date(),
            processingStatus: .processing,
            processingError: nil
        )
        session.photos.insert(photo, at: 0)

        do {
            let cinematicData = try await generationService.enhanceShotCinematic(
                imageData: imageData,
                prompt: PromptExpander.cinematicMemoryPhotoEdit()
            )
            dispatch(.memoryPhotoCinematicReady(id: photoId, imageData: cinematicData))
        } catch {
            dispatch(.memoryPhotoCinematicFailed(id: photoId, error: error.localizedDescription))
        }
    }

    private func loadDefaultCatImageData() -> Data? {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let candidates: [URL] = [
            Bundle.main.url(forResource: "cat", withExtension: "jpg"),
            Bundle.main.url(forResource: "cat", withExtension: "jpeg"),
            home.appendingPathComponent("pictures/cat.jpg"),
            home.appendingPathComponent("Pictures/cat.jpg"),
            home.appendingPathComponent("varicklim/pictures/cat.jpg"),
            URL(fileURLWithPath: "/Users/varicklim/pictures/cat.jpg"),
        ].compactMap { $0 }

        for url in candidates {
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    // MARK: - Agent-friendly state export

    var sessionJSON: [String: Any] {
        [
            "phase": session.phase.rawValue,
            "environment": session.environment.map {
                ["status": $0.status.rawValue, "prompt": $0.voicePrompt]
            } as Any,
            "hero": session.hero.map {
                ["name": $0.name, "status": $0.status.rawValue, "prompt": $0.voicePrompt]
            } as Any,
            "villain": session.villain.map {
                ["name": $0.name, "status": $0.status.rawValue, "prompt": $0.voicePrompt]
            } as Any,
            "shotsCount": session.shots.count,
            "shots": session.shots.map {
                ["index": $0.index, "angle": $0.cameraAngle.rawValue]
            },
            "photosCount": session.photos.count,
            "videosCount": session.videos.count,
            "clipsCount": session.clips.count,
            "canShoot": session.canShoot,
            "canGenerate": session.canGenerate,
        ]
    }
}

// MARK: - Service Protocols (swap for real implementations)

protocol GenerationServiceProtocol {
    func generateSkybox(_ prompt: String) async throws -> URL
    func generateCharacter(_ prompt: String) async throws -> URL
    func generateClip(frames: [UIImage], shots: [ARShot], style: CinematicStyle, audioPrompt: String) async throws -> URL
    func enhanceShotCinematic(imageData: Data, prompt: String) async throws -> Data
    func animateImageToVideo(imageData: Data, prompt: String) async throws -> URL
}

protocol ARSceneProtocol {
    func applySkybox(_ url: URL)
    func captureFrame() -> UIImage
    func removeWorld()
    func removeCharacter(slot: CharacterSlot)
    func reset()
    var currentCameraTransform: simd_float4x4 { get }
    var visibleCharacterSlots: [CharacterSlot] { get }
}

// MARK: - Prompt Expander (GPT-5 calls go here)

enum PromptExpander {
    static func environment(_ raw: String) -> String {
        // TODO: call GPT-5 to expand into rich skybox prompt
        // For now: passthrough + fantasy defaults
        "\(raw), fantasy landscape, dramatic lighting, epic scale, cinematic atmosphere"
    }

    static func character(_ raw: String, slot: CharacterSlot) -> String {
        let pose = "T-pose, neutral expression, centered, full body, no background"
        let quality = "high detail PBR textures, game-ready, 3D model reference sheet"
        let slotHint = slot == .hero ? "heroic warrior" : "menacing villain creature"
        return "\(raw), \(slotHint), \(pose), \(quality)"
    }

    static func shot(angle: CameraAngle, session: FilmSession, index: Int) -> String {
        let env = session.environment?.voicePrompt ?? "fantasy battlefield"
        let hero = session.hero?.name ?? "warrior"
        let villain = session.villain?.name ?? "monster"

        switch angle {
        case .wideEstablishing:
            return "Shot \(index): Wide establishing shot, \(hero) and \(villain) face off in \(env), slow push in, cinematic"
        case .mediumTwoShot:
            return "Shot \(index): Medium two-shot, \(hero) and \(villain), tension, \(env)"
        case .closeUpFace:
            return "Shot \(index): Extreme close-up face, intense gaze, dramatic lighting, \(env)"
        case .overTheShoulder:
            return "Shot \(index): Over-the-shoulder shot, \(hero) facing \(villain), \(env)"
        case .lowAngleHeroic:
            return "Shot \(index): Low angle heroic shot looking up at \(hero), looming, powerful"
        case .insertDetail:
            return "Shot \(index): Detail insert shot, weapon or hands, sharp focus, bokeh background"
        default:
            return "Shot \(index): \(angle.displayName) shot, \(hero) vs \(villain), \(env), cinematic"
        }
    }

    static func cinematicShotEdit(angle: CameraAngle, session: FilmSession, index: Int) -> String {
        let env = session.environment?.voicePrompt ?? "fantasy battlefield"
        let hero = session.hero?.name ?? "warrior"
        let villain = session.villain?.name ?? "monster"

        return """
        You are a senior colorist and DI artist. Transform this into a cinematic movie still while preserving the exact composition.
        Preserve exactly: framing, crop, lens perspective, camera position, character identity, facial features, pose, hand placement, costume, props, and environment layout.
        Do not add/remove subjects, do not reframe, do not zoom, and do not add text or watermark.
        Repair 3D/render artifacts while preserving silhouette and intent: fix broken topology, non-manifold-looking surfaces, clipping/intersections, UV seams/stretching, texture misalignment, low-poly faceting, jagged edges, z-fighting, and shading/bake glitches. Replace placeholder or low-resolution materials with coherent, physically plausible detail that matches the original design.
        Apply cinematic finishing: filmic color grading, richer dynamic range, controlled highlights, soft highlight roll-off, clean skin tones, nuanced shadow contrast, subtle atmospheric depth, and premium blockbuster polish.
        Keep continuity with this scene: \(env). Subject context: \(hero) versus \(villain). Shot \(index), \(angle.displayName).
        """
    }

    static func cinematicMemoryPhotoEdit() -> String {
        """
        You are a senior colorist and DI artist. Transform this image into a cinematic movie still while preserving exact composition.
        Preserve exactly: framing, crop, lens perspective, subject identity, facial features, pose, and background layout.
        Do not add/remove subjects, do not reframe, do not zoom, do not change geometry, and do not add text or watermark.
        Apply only cinematic finishing: filmic color grading, richer dynamic range, controlled highlights, soft highlight roll-off, nuanced shadow contrast, subtle atmospheric depth, and premium blockbuster polish.
        """
    }
}

// MARK: - Mock Services (for development/preview)

final class NoopARScene: ARSceneProtocol {
    static let shared = NoopARScene()

    private init() {}

    func applySkybox(_ url: URL) {}

    func captureFrame() -> UIImage { UIImage() }

    func removeWorld() {}

    func removeCharacter(slot: CharacterSlot) {}

    func reset() {}

    var currentCameraTransform: simd_float4x4 { matrix_identity_float4x4 }

    var visibleCharacterSlots: [CharacterSlot] { [] }
}

final class MockGenerationService: GenerationServiceProtocol {
    func generateSkybox(_ prompt: String) async throws -> URL {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        if let sampleSkybox = Bundle.main.url(forResource: "sample_360", withExtension: "hdr") {
            return sampleSkybox
        }

        if let fallbackSkybox = Bundle.main.url(forResource: "sample_640×426", withExtension: "hdr") {
            return fallbackSkybox
        }

        throw NSError(
            domain: "MockGenerationService",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing sample 360 background file"]
        )
    }

    func generateCharacter(_ prompt: String) async throws -> URL {
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let normalizedPrompt = prompt.lowercased()
        let isMonsterPrompt = normalizedPrompt.contains("villain")
            || normalizedPrompt.contains("monster")
            || normalizedPrompt.contains("creature")
            || normalizedPrompt.contains("menacing")

        if isMonsterPrompt, let monsterURL = Bundle.main.url(forResource: "spider_creature", withExtension: "usdz") {
            return monsterURL
        }

        if let warriorURL = Bundle.main.url(forResource: "rex", withExtension: "usdz") {
            return warriorURL
        }

        if let fallbackMonsterURL = Bundle.main.url(forResource: "spider_creature", withExtension: "usdz") {
            return fallbackMonsterURL
        }

        if let demoURL = Bundle.main.url(forResource: "demo_character", withExtension: "usdz") {
            return demoURL
        }

        throw NSError(
            domain: "MockGenerationService",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Missing default 3D character files"]
        )
    }

    func generateClip(frames: [UIImage], shots: [ARShot], style: CinematicStyle, audioPrompt: String) async throws -> URL {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return URL(string: "https://example.com/clip.mp4")!
    }

    func enhanceShotCinematic(imageData: Data, prompt: String) async throws -> Data {
        imageData
    }

    func animateImageToVideo(imageData: Data, prompt: String) async throws -> URL {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        return URL(string: "https://example.com/animation.mp4")!
    }
}

final class HybridGenerationService: GenerationServiceProtocol {
    private let fallback: GenerationServiceProtocol
    private let falService: FalService

    init(
        fallback: GenerationServiceProtocol = MockGenerationService(),
        falService: FalService = FalService()
    ) {
        self.fallback = fallback
        self.falService = falService
    }

    func generateSkybox(_ prompt: String) async throws -> URL {
        try await fallback.generateSkybox(prompt)
    }

    func generateCharacter(_ prompt: String) async throws -> URL {
        try await fallback.generateCharacter(prompt)
    }

    func generateClip(frames: [UIImage], shots: [ARShot], style: CinematicStyle, audioPrompt: String) async throws -> URL {
        try await fallback.generateClip(frames: frames, shots: shots, style: style, audioPrompt: audioPrompt)
    }

    func enhanceShotCinematic(imageData: Data, prompt: String) async throws -> Data {
        try await falService.cinematicShotFlux2Pro(imageData: imageData, prompt: prompt)
    }

    func animateImageToVideo(imageData: Data, prompt: String) async throws -> URL {
        try await falService.animateImageSeedanceFast(imageData: imageData, prompt: prompt)
    }
}
