import Foundation
import UIKit
import simd

enum ShotType: String, CaseIterable, Sendable {
    case wide = "Wide Shot"
    case closeUp = "Close Up"
    case overShoulder = "Over the Shoulder"
    case custom = "Custom"
}

struct Shot: Identifiable {
    let id: UUID
    var type: ShotType
    var capturedFrame: UIImage
    var cameraTransform: simd_float4x4?

    init(type: ShotType, capturedFrame: UIImage, cameraTransform: simd_float4x4? = nil) {
        self.id = UUID()
        self.type = type
        self.capturedFrame = capturedFrame
        self.cameraTransform = cameraTransform
    }
}
