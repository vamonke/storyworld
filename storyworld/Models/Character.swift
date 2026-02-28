import Foundation
import RealityKit
import UIKit

struct Character: Identifiable {
    let id: UUID
    var name: String
    var originalPhoto: Data
    var stylizedImage: Data?
    var modelURL: URL?
    var modelEntity: ModelEntity?

    init(name: String, originalPhoto: Data) {
        self.id = UUID()
        self.name = name
        self.originalPhoto = originalPhoto
    }

    /// Create a character from a pre-loaded 3D model (no photo needed)
    init(name: String, modelURL: URL, modelEntity: ModelEntity) {
        self.id = UUID()
        self.name = name
        self.originalPhoto = Data() // empty placeholder
        self.modelURL = modelURL
        self.modelEntity = modelEntity
    }

    /// Create a character from a model URL that can be loaded lazily later.
    init(name: String, modelURL: URL) {
        self.id = UUID()
        self.name = name
        self.originalPhoto = Data()
        self.modelURL = modelURL
        self.modelEntity = nil
    }

    var originalUIImage: UIImage? {
        UIImage(data: originalPhoto)
    }

    var stylizedUIImage: UIImage? {
        guard let data = stylizedImage else { return nil }
        return UIImage(data: data)
    }
}
