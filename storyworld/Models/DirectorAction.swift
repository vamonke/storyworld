import Foundation

enum VoiceDirectorAction: Sendable {
    case captureShot
    case changeExpression(String)
    case changePose(String)
    case changeOutfit(String)
    case suggestFraming(ShotType)
    case generate(scenePrompt: String)
    case unknown(String)
}
