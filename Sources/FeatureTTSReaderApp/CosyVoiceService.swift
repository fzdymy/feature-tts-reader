import Foundation
import CosyVoiceTTS
import AudioCommon

// MARK: - On-device CosyVoice 3 TTS engine

actor CosyVoiceService {
    static let shared = CosyVoiceService()

    private var ttsModel: CosyVoiceTTSModel?
    private var camppSpeaker: CamPlusPlusSpeaker?

    var isAvailable: Bool { ttsModel != nil }

    // MARK: - Lifecycle

    func ensureModel() async throws {
        guard ttsModel == nil else { return }
        ttsModel = try await CosyVoiceTTSModel.fromPretrained()
        try Task.checkCancellation()
        ttsModel?.warmUp()
    }

    /// Extract 192-dim CAM++ speaker embedding from a reference audio file.
    func enrollSpeaker(name: String, audioURL: URL) async throws -> [Float] {
        let campp: CamPlusPlusSpeaker
        if let existing = camppSpeaker {
            campp = existing
        } else {
            campp = try await CamPlusPlusSpeaker.fromPretrained()
            camppSpeaker = campp
        }
        let audio = try AudioFileLoader.load(url: audioURL, targetSampleRate: 16_000)
        return try campp.embed(audio: audio, sampleRate: 16_000)
    }

    // MARK: - Dialogue Synthesis

    /// Synthesize multi-speaker dialogue as 24kHz WAV data.
    func synthesizeDialogue(
        segments: [(speaker: String, text: String, emotion: String?)],
        speakerSamples: [String: URL]
    ) async throws -> Data {
        try await ensureModel()
        guard let model = ttsModel else { throw TTSError.modelNotAvailable }

        // 1. Enroll speakers (CAM++ embeddings)
        var embeddings: [String: [Float]] = [:]
        for (name, url) in speakerSamples {
            if let emb = try? await enrollSpeaker(name: name, audioURL: url) {
                embeddings[name] = emb
            }
        }

        // 2. Build DialogueSegment array with emotion tags
        let dialogueSegments: [DialogueSegment] = segments.map { spk, text, emotion in
            let emo = emotion.flatMap { Self.cosyEmotionTag($0) }
            return DialogueSegment(speaker: spk, emotion: emo, text: text)
        }

        // 3. Synthesize
        let samples = try DialogueSynthesizer.synthesize(
            segments: dialogueSegments,
            speakerEmbeddings: embeddings,
            model: model,
            language: "chinese",
            config: DialogueSynthesisConfig(turnGapSeconds: 0.2)
        )

        // 4. Convert [Float] samples to WAV data
        return AudioConverter.floatToWAV(samples, sampleRate: 24_000)
    }

    /// Synthesize a single speaker's text (for previews).
    func synthesizeSingle(text: String, embedding: [Float]? = nil) async throws -> Data {
        try await ensureModel()
        guard let model = ttsModel else { throw TTSError.modelNotAvailable }

        let samples: [Float]
        if let emb = embedding {
            samples = model.synthesize(text: text, language: "chinese", speakerEmbedding: emb)
        } else {
            samples = model.synthesize(text: text, language: "chinese")
        }
        return AudioConverter.floatToWAV(samples, sampleRate: 24_000)
    }

    // MARK: - Emotion tag mapping

    private static func cosyEmotionTag(_ emotion: String) -> String? {
        switch emotion.lowercased() {
        case "angry":      return "angry"
        case "sad":        return "sad"
        case "happy",
             "cheerful":   return "happy"
        case "whisper",
             "whispering": return "whispers"
        case "laugh",
             "laughing":   return "laughs"
        case "calm":       return "calm"
        case "surprised":  return "surprised"
        case "serious":    return "serious"
        default:           return nil
        }
    }
}

// MARK: - Audio conversion helpers

enum AudioConverter {
    /// Convert [Float] audio samples to WAV format Data (mono, 16-bit PCM).
    static func floatToWAV(_ samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        // WAV header
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)
        let fileSize = 36 + dataSize

        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: fileSize.littleEndianBytes)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.append(contentsOf: UInt32(16).littleEndianBytes) // chunk size
        data.append(contentsOf: UInt16(1).littleEndianBytes)  // PCM
        data.append(contentsOf: numChannels.littleEndianBytes)
        data.append(contentsOf: UInt32(sampleRate).littleEndianBytes)
        data.append(contentsOf: byteRate.littleEndianBytes)
        data.append(contentsOf: blockAlign.littleEndianBytes)
        data.append(contentsOf: bitsPerSample.littleEndianBytes)

        // data chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: dataSize.littleEndianBytes)

        // PCM samples
        for sample in samples {
            let clamped = max(-1.0, min(1.0, Double(sample)))
            let int16 = Int16(clamped * Double(Int16.max))
            data.append(contentsOf: int16.littleEndianBytes)
        }

        return data
    }
}

// MARK: - Little-endian byte helpers

private extension UInt16 {
    var littleEndianBytes: [UInt8] {
        [UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF)]
    }
}

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        [UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF),
         UInt8((self >> 16) & 0xFF), UInt8((self >> 24) & 0xFF)]
    }
}

private extension Int16 {
    var littleEndianBytes: [UInt8] {
        [UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF)]
    }
}

// MARK: - Errors

enum TTSError: LocalizedError {
    case modelNotAvailable
    case synthesisFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable: return "CosyVoice 模型未加载，请检查网络连接后重试"
        case .synthesisFailed(let msg): return "语音合成失败: \(msg)"
        }
    }
}
