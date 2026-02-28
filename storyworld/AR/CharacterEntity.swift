import RealityKit
import UIKit

class CharacterEntity {
    let character: Character
    var entity: ModelEntity?

    init(character: Character) {
        self.character = character
    }

    func loadOrCreatePlaceholder() async -> ModelEntity {
        if let existing = character.modelEntity {
            return existing.clone(recursive: true)
        }

        if let modelURL = character.modelURL {
            do {
                let loaded = try await ModelEntity(contentsOf: modelURL)
                if modelURL.lastPathComponent.hasPrefix(devSampleTextTo3DDownloadedFilenamePrefix) {
                    let xAxisFix = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
                    loaded.orientation = simd_mul(xAxisFix, loaded.orientation)
                }
                loaded.generateCollisionShapes(recursive: true)
                self.entity = loaded
                return loaded
            } catch {
                // Fallback to placeholder if model loading fails.
            }
        }

        // Create a placeholder box with the character's image as texture
        let mesh = MeshResource.generateBox(size: 0.3)
        var material = SimpleMaterial()

        if let imageData = character.stylizedImage ?? Optional(character.originalPhoto),
           let uiImage = UIImage(data: imageData),
           let cgImage = uiImage.cgImage {
            do {
                let texture = try await TextureResource(image: cgImage, options: .init(semantic: .color))
                material.color = .init(tint: .white, texture: .init(texture))
            } catch {
                material.color = .init(tint: .systemBlue)
            }
        } else {
            material.color = .init(tint: .systemBlue)
        }

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.generateCollisionShapes(recursive: true)
        self.entity = entity
        return entity
    }
}
