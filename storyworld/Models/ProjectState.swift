import Foundation
import SwiftUI
import Observation
import RealityKit

enum AppFlowState: Equatable {
    case welcome
    case capture
    case stylize
    case arDirector
    case generate
    case playback
}

@Observable
class ProjectState {
    var flowState: AppFlowState = .welcome
    var project = Project()

    var currentCharacterIndex: Int = 0
    var isProcessing: Bool = false
    var processingMessage: String = ""
    var errorMessage: String?

    // Generation status
    var stylizationProgress: Double = 0
    var modelGenerationProgress: Double = 0
    var videoGenerationProgress: Double = 0

    var characters: [Character] {
        get { project.characters }
        set { project.characters = newValue }
    }

    var shots: [Shot] {
        get { project.shots }
        set { project.shots = newValue }
    }

    init() {
        seedDefaultPlacementCharacters()
    }

    func addCharacter(_ character: Character) {
        project.characters.append(character)
    }

    func addShot(_ shot: Shot) {
        project.shots.append(shot)
    }

    func removeShot(at index: Int) {
        guard index < project.shots.count else { return }
        project.shots.remove(at: index)
    }

    /// Load bundled 3D model and jump straight to AR
    func loadDemoModel() async {
        isProcessing = true
        processingMessage = "Loading 3D model..."

        do {
            guard let bundleURL = Bundle.main.url(forResource: "demo_character", withExtension: "usdz") else {
                throw NSError(domain: "StoryWorld", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model file not found in bundle"])
            }

            let entity = try await ModelEntity(contentsOf: bundleURL)
            entity.generateCollisionShapes(recursive: true)

            let character = Character(name: "Robot", modelURL: bundleURL, modelEntity: entity)
            addCharacter(character)

            isProcessing = false
            processingMessage = ""
            flowState = .arDirector
        } catch {
            isProcessing = false
            processingMessage = ""
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }
    }

    func reset() {
        flowState = .welcome
        project = Project()
        seedDefaultPlacementCharacters()
        currentCharacterIndex = 0
        isProcessing = false
        processingMessage = ""
        errorMessage = nil
        stylizationProgress = 0
        modelGenerationProgress = 0
        videoGenerationProgress = 0
    }

    private func seedDefaultPlacementCharacters() {
        guard project.characters.isEmpty else { return }

        if let warriorURL = Bundle.main.url(forResource: "rex", withExtension: "usdz") {
            project.characters.append(Character(name: "Warrior (Rex)", modelURL: warriorURL))
        }

        if let monsterURL = Bundle.main.url(forResource: "spider_creature", withExtension: "usdz") {
            project.characters.append(Character(name: "Monster (Spider)", modelURL: monsterURL))
        }
    }
}
