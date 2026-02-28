import Foundation

struct Project: Identifiable {
    let id: UUID
    var characters: [Character]
    var shots: [Shot]
    var scenePrompt: String
    var generatedVideoURL: URL?

    init() {
        self.id = UUID()
        self.characters = []
        self.shots = []
        self.scenePrompt = ""
    }
}
