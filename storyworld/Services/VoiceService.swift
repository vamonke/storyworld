import AVFoundation
import Foundation

@Observable
class VoiceService {
    var isListening = false
    var lastTranscription = ""
    var lastAction: VoiceDirectorAction?

    private var audioEngine: AVAudioEngine?
    private var audioBuffer = Data()
    private let openAIClient = OpenAIClient()

    func startListening() {
        guard !isListening else { return }
        audioBuffer = Data()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
        } catch {
            return
        }

        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let data = self.bufferToData(buffer: buffer)
            self.audioBuffer.append(data)
        }

        do {
            try audioEngine.start()
            isListening = true
        } catch {
            return
        }
    }

    func cancelListening() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isListening = false
        audioBuffer = Data()
    }

    func stopListeningAndTranscribe() async -> String? {
        let pcmData = stopListeningAndExtractPCM()
        guard !pcmData.isEmpty else { return nil }

        let wavData = createWAV(from: pcmData)

        do {
            let transcription = try await openAIClient.transcribe(audioData: wavData)
            lastTranscription = transcription
            return transcription
        } catch {
            return nil
        }
    }

    func stopListeningAndProcess() async -> VoiceDirectorAction? {
        guard let transcription = await stopListeningAndTranscribe() else { return nil }

        do {
            let action = try await openAIClient.parseIntent(text: transcription)
            lastAction = action
            return action
        } catch {
            return nil
        }
    }

    private func stopListeningAndExtractPCM() -> Data {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isListening = false

        let pcmData = audioBuffer
        audioBuffer = Data()
        return pcmData
    }

    private nonisolated func bufferToData(buffer: AVAudioPCMBuffer) -> Data {
        let channels = UnsafeBufferPointer(start: buffer.floatChannelData, count: Int(buffer.format.channelCount))
        let frameLength = Int(buffer.frameLength)
        var data = Data(capacity: frameLength * 2)

        for i in 0..<frameLength {
            let sample = channels[0][i]
            var int16Sample = Int16(max(-1, min(1, sample)) * Float(Int16.max))
            data.append(Data(bytes: &int16Sample, count: 2))
        }

        return data
    }

    private func createWAV(from pcmData: Data) -> Data {
        let sampleRate: UInt32 = 44100
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // PCM
        header.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        header.append(contentsOf: "data".utf8)
        header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })

        return header + pcmData
    }
}
