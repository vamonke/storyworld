import Foundation
import RealityKit

class ModelLoader {
    private let falClient = FalService()

    func generateAndLoad(from imageData: Data) async throws -> (URL, ModelEntity) {
        let modelURL = try await falClient.generate3DModel(imageData: imageData)
        let entity = try await loadEntity(from: modelURL)
        return (modelURL, entity)
    }

    func loadEntity(from url: URL) async throws -> ModelEntity {
        let entity = try await ModelEntity(contentsOf: url)
        entity.generateCollisionShapes(recursive: true)
        return entity
    }

    /// Download a USDZ model from a remote URL and return the local file URL + loaded entity
    func downloadAndLoad(from remoteURL: URL) async throws -> (URL, ModelEntity) {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let localURL = cacheDir.appendingPathComponent(remoteURL.lastPathComponent)

        // Use cached file if it exists
        if !FileManager.default.fileExists(atPath: localURL.path) {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            try data.write(to: localURL)
        }

        let entity = try await loadEntity(from: localURL)
        return (localURL, entity)
    }
}
