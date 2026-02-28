import ARKit
import RealityKit
import Combine
import UIKit
import CoreImage

final class ARSessionManager: ARSceneProtocol {
    let arView: ARView

    // Preview entity that follows the raycast hit point
    private var previewEntity: ModelEntity?
    private var previewAnchor: AnchorEntity?
    private var displayLink: CADisplayLink?

    // Track whether we have a valid surface hit
    var hasValidPlacement: Bool = false
    private var currentHitPosition: SIMD3<Float>?
    private var worldAnchor: AnchorEntity?
    private var worldPlaneEntity: ModelEntity?
    private let ciContext = CIContext()
    private var worldPlaneYOffset: Float = -0.22
    private let floorTextureResourceName = "rock_face_03_diff_2k"
    private let floorFallbackColor = UIColor(red: 0.31, green: 0.27, blue: 0.21, alpha: 0.92)
    private var placedCharacters: [CharacterSlot: ModelEntity] = [:]
    private var placedCharacterAnchors: [CharacterSlot: AnchorEntity] = [:]
    private var characterScaleMultipliers: [CharacterSlot: Float] = [:]
    private var characterYawDegrees: [CharacterSlot: Float] = [:]

    // Y-axis rotation controlled by drag gesture
    var previewYRotation: Float = 0
    // Scale controlled by slider (1.0 = default 0.3 base scale)
    var previewScaleMultiplier: Float = 1.0

    init() {
        arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
    }

    func startSession() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)
        startPreviewUpdates()

        // Add coaching overlay to guide user to find surfaces
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .horizontalPlane
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.addSubview(coachingOverlay)
    }

    func stopSession() {
        stopPreviewUpdates()
        arView.session.pause()
    }

    // MARK: - Preview (ghost that follows screen center)

    func startPreview(with entity: ModelEntity) {
        // Create a semi-transparent clone as the preview
        let preview = entity.clone(recursive: true)
        preview.scale = SIMD3<Float>(repeating: 0.3)

        // Make it semi-transparent
        if var model = preview.model {
            model.materials = model.materials.map { _ in
                var mat = SimpleMaterial()
                mat.color = .init(tint: .white.withAlphaComponent(0.5))
                return mat
            }
            preview.model = model
        }

        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(preview)
        arView.scene.addAnchor(anchor)

        previewEntity = preview
        previewAnchor = anchor

        // Preview pose follows the same session-wide update loop.
    }

    func stopPreview() {
        if let anchor = previewAnchor {
            arView.scene.removeAnchor(anchor)
        }
        previewEntity = nil
        previewAnchor = nil
    }

    private func startPreviewUpdates() {
        guard displayLink == nil else { return }
        displayLink = CADisplayLink(target: self, selector: #selector(updatePreview))
        displayLink?.add(to: .main, forMode: .default)
    }

    private func stopPreviewUpdates() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updatePreview() {
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)

        let results = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal)

        if let result = results.first {
            let position = SIMD3<Float>(
                result.worldTransform.columns.3.x,
                result.worldTransform.columns.3.y,
                result.worldTransform.columns.3.z
            )
            previewAnchor?.transform.translation = position
            let s = 0.3 * previewScaleMultiplier
            previewEntity?.scale = SIMD3<Float>(repeating: s)
            previewEntity?.orientation = simd_quatf(angle: previewYRotation, axis: SIMD3<Float>(0, 1, 0))
            previewEntity?.isEnabled = true
            currentHitPosition = position
            hasValidPlacement = true
        } else {
            previewEntity?.isEnabled = false
            hasValidPlacement = false
            currentHitPosition = nil
        }
    }

    // MARK: - Placement (anchor at current hit point)

    func placeAtCurrentPosition(_ entity: ModelEntity) -> Bool {
        guard let position = currentHitPosition else { return false }

        let anchor = AnchorEntity(world: position)
        let s = 0.3 * previewScaleMultiplier
        entity.scale = SIMD3<Float>(repeating: s)
        entity.orientation = simd_quatf(angle: previewYRotation, axis: SIMD3<Float>(0, 1, 0))
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)

        // Reset for next placement
        previewYRotation = 0
        previewScaleMultiplier = 1.0
        return true
    }

    func placeCharacter(_ entity: ModelEntity, at position: SIMD3<Float>) {
        let anchor = AnchorEntity(world: position)
        entity.scale = SIMD3<Float>(repeating: 0.3)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
    }

    func placeOnPlane(_ entity: ModelEntity) {
        let anchor = AnchorEntity(world: SIMD3<Float>(0, -0.5, -1.5))
        entity.scale = SIMD3<Float>(repeating: 0.5)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
    }

    func captureSnapshot() async -> UIImage? {
        await withCheckedContinuation { continuation in
            arView.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
    }

    func applySkybox(_ url: URL) {
        clearWorldAnchor()

        if let environment = try? EnvironmentResource.__load(contentsOf: url) {
            arView.environment.background = .skybox(environment)
            arView.environment.lighting.resource = environment
            arView.environment.lighting.intensityExponent = 1.0
        }

        // Add a visible "battlefield" ground so world setup has a clear AR result.
        let groundAnchor = AnchorEntity(world: currentHitPosition ?? SIMD3<Float>(0, -0.5, -1.5))
        let ground = ModelEntity(
            mesh: .generatePlane(width: 4.0, depth: 4.0),
            materials: [makeMatteFloorMaterial()]
        )
        ground.position = SIMD3<Float>(0, worldPlaneYOffset, 0)
        groundAnchor.addChild(ground)
        arView.scene.addAnchor(groundAnchor)
        worldAnchor = groundAnchor
        worldPlaneEntity = ground
        applyFloorTextureIfAvailable(to: ground)
    }

    func captureFrame() -> UIImage {
        guard let frame = arView.session.currentFrame else {
            return UIImage()
        }
        let ciImage = CIImage(cvPixelBuffer: frame.capturedImage)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return UIImage()
        }
        return UIImage(cgImage: cgImage)
    }

    func reset() {
        stopPreview()
        clearWorldAnchor()
        hasValidPlacement = false
        currentHitPosition = nil
        previewYRotation = 0
        previewScaleMultiplier = 1.0
        placedCharacters = [:]
        placedCharacterAnchors = [:]
        characterScaleMultipliers = [:]
        characterYawDegrees = [:]
        for anchor in arView.scene.anchors {
            arView.scene.removeAnchor(anchor)
        }
    }

    var currentCameraTransform: simd_float4x4 {
        arView.session.currentFrame?.camera.transform ?? matrix_identity_float4x4
    }

    var visibleCharacterSlots: [CharacterSlot] {
        Array(placedCharacters.keys)
    }

    var worldPlaneYOffsetValue: Float {
        worldPlaneYOffset
    }

    func setWorldPlaneYOffset(_ offset: Float) {
        worldPlaneYOffset = offset
        worldPlaneEntity?.position.y = offset
    }

    func registerPlacedCharacter(_ entity: ModelEntity, slot: CharacterSlot) {
        placedCharacters[slot] = entity
        if let anchor = entity.anchor as? AnchorEntity {
            placedCharacterAnchors[slot] = anchor
        }
        characterScaleMultipliers[slot] = max(entity.scale.x / 0.3, 0.01)
        characterYawDegrees[slot] = yawDegrees(for: entity.orientation)
    }

    func characterScaleMultiplier(for slot: CharacterSlot) -> Float {
        if let entity = placedCharacters[slot] {
            return max(entity.scale.x / 0.3, 0.01)
        }
        return characterScaleMultipliers[slot] ?? 1.0
    }

    func setCharacterScaleMultiplier(_ multiplier: Float, slot: CharacterSlot) {
        let clamped = max(multiplier, 0.1)
        characterScaleMultipliers[slot] = clamped
        placedCharacters[slot]?.scale = SIMD3<Float>(repeating: 0.3 * clamped)
    }

    func characterYawDegrees(for slot: CharacterSlot) -> Float {
        if let entity = placedCharacters[slot] {
            return yawDegrees(for: entity.orientation)
        }
        return characterYawDegrees[slot] ?? 0
    }

    func setCharacterYawDegrees(_ degrees: Float, slot: CharacterSlot) {
        characterYawDegrees[slot] = degrees
        let radians = degrees * .pi / 180
        placedCharacters[slot]?.orientation = simd_quatf(angle: radians, axis: SIMD3<Float>(0, 1, 0))
    }

    func hasPlacedCharacter(_ slot: CharacterSlot) -> Bool {
        placedCharacters[slot] != nil
    }

    func removeWorld() {
        clearWorldAnchor()
        arView.environment.background = .cameraFeed()
        arView.environment.lighting.resource = nil
    }

    func removeCharacter(slot: CharacterSlot) {
        if let entity = placedCharacters[slot] {
            entity.removeFromParent()
        }
        if let anchor = placedCharacterAnchors[slot] {
            arView.scene.removeAnchor(anchor)
        }
        placedCharacters[slot] = nil
        placedCharacterAnchors[slot] = nil
        characterScaleMultipliers[slot] = nil
        characterYawDegrees[slot] = nil
    }

    private func yawDegrees(for orientation: simd_quatf) -> Float {
        let q = orientation.vector
        let sinyCosp = 2 * (q.w * q.y + q.x * q.z)
        let cosyCosp = 1 - 2 * (q.y * q.y + q.z * q.z)
        let radians = atan2(sinyCosp, cosyCosp)
        return radians * 180 / .pi
    }

    private func applyFloorTextureIfAvailable(to ground: ModelEntity) {
        guard
            let textureURL = Bundle.main.url(forResource: floorTextureResourceName, withExtension: "jpg"),
            let image = UIImage(contentsOfFile: textureURL.path),
            let cgImage = image.cgImage
        else {
            return
        }

        Task { @MainActor in
            do {
                let texture = try await TextureResource(image: cgImage, options: .init(semantic: .color))
                let material = makeMatteFloorMaterial(texture: texture)
                ground.model?.materials = [material]
            } catch {
                // Keep fallback color material when texture loading fails.
            }
        }
    }

    private func makeMatteFloorMaterial(texture: TextureResource? = nil) -> SimpleMaterial {
        var material = SimpleMaterial()
        material.roughness = .float(1.0)
        material.metallic = .float(0.0)

        // Slightly dark tint keeps bright HDR skyboxes from washing out the ground.
        if let texture {
            material.color = .init(tint: UIColor(white: 0.78, alpha: 1.0), texture: .init(texture))
        } else {
            material.color = .init(tint: floorFallbackColor)
        }

        return material
    }

    private func clearWorldAnchor() {
        if let worldAnchor {
            arView.scene.removeAnchor(worldAnchor)
            self.worldAnchor = nil
        }
        worldPlaneEntity = nil
    }
}
