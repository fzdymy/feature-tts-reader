import Foundation
import CoreML
import Accelerate

// MARK: - BERT-based speaker detector

final class BertSpeakerDetector {
    struct Config {
        static let maxLength = 128
        static let embeddingDim = 768

        static let clsTokenID: Int32 = 101
        static let sepTokenID: Int32 = 102
        static let padTokenID: Int32 = 0
        static let unkTokenID: Int32 = 100
    }

    private var model: MLModel?
    private let tokenizer: BertTokenizer

    private var profileEmbeddings: [String: [Float]] = [:]

    var isAvailable: Bool { model != nil }

    init() {
        self.tokenizer = BertTokenizer()
        loadModel()
    }

    // MARK: - Public API

    /// Get embedding for any text.
    func embed(_ text: String) -> [Float]? {
        guard let model = model else { return nil }
        let (ids, mask) = tokenizer.tokenize(text, maxLength: Config.maxLength)
        guard let multiArray = makeMultiArray(ids) else { return nil }
        guard let maskArray = makeMultiArray(mask) else { return nil }
        guard let output = try? model.prediction(from: BertInput(input_ids: multiArray, attention_mask: maskArray)) else { return nil }
        guard let embedding = output.featureValue(for: "embedding")?.multiArrayValue else { return nil }
        return extractFloats(from: embedding)
    }

    /// Build or update a profile embedding for a character from known text.
    func updateProfile(for character: String, from text: String) {
        guard let emb = embed(text) else { return }
        if var existing = profileEmbeddings[character] {
            // Running average
            for i in existing.indices { existing[i] = (existing[i] + emb[i]) * 0.5 }
            profileEmbeddings[character] = existing
        } else {
            profileEmbeddings[character] = emb
        }
    }

    /// Find the best matching character for a given embedding.
    func bestMatch(for query: [Float], candidates: [String]) -> (name: String, score: Float)? {
        var best: (String, Float)? = nil
        for name in candidates {
            guard let profile = profileEmbeddings[name] else { continue }
            let sim = cosineSimilarity(query, profile)
            if sim > (best?.1 ?? -1) { best = (name, sim) }
        }
        return best
    }

    /// Reset all profiles (e.g. at the start of a new chapter).
    func resetProfiles() {
        profileEmbeddings = [:]
    }

    /// Convenience: embed text and find best match from known profiles.
    func detectSpeaker(context: String, quote: String, candidates: [String]) -> (name: String?, score: Float) {
        let input = context + " [SEP] " + quote
        guard let emb = embed(input) else { return (nil, 0) }
        if let (name, score) = bestMatch(for: emb, candidates: candidates) {
            return (name, score)
        }
        return (nil, 0)
    }

    // MARK: - Private

    private func loadModel() {
        guard let url = Bundle.module.url(forResource: "distilbert_chinese", withExtension: "mlpackage") else {
            print("[BertSpeakerDetector] Model not found in bundle")
            return
        }
        do {
            model = try MLModel(contentsOf: url)
        } catch {
            print("[BertSpeakerDetector] Failed to load model: \(error)")
        }
    }

    private func makeMultiArray(_ values: [Int32]) -> MLMultiArray? {
        let shape = [1, NSNumber(value: Config.maxLength)]
        guard let arr = try? MLMultiArray(shape: shape, dataType: .int32) else { return nil }
        for (i, v) in values.enumerated() { arr[i] = NSNumber(value: v) }
        return arr
    }

    private func extractFloats(from multi: MLMultiArray) -> [Float] {
        let count = multi.count
        var result = [Float](repeating: 0, count: count)
        for i in 0..<count { result[i] = multi[i].floatValue }
        return result
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for (x, y) in zip(a, b) {
            dot += x * y
            normA += x * x
            normB += y * y
        }
        return dot / (sqrt(normA) * sqrt(normB) + 1e-10)
    }
}

// MARK: - BERT Tokenizer (Chinese character-level)

final class BertTokenizer {
    private var vocab: [String: Int32] = [:]
    private var idToToken: [Int32: String] = [:]

    init() {
        loadVocab()
    }

    func tokenize(_ text: String, maxLength: Int) -> (inputIds: [Int32], attentionMask: [Int32]) {
        var ids: [Int32] = [Int32(BertSpeakerDetector.Config.clsTokenID)]

        for ch in text {
            let key = String(ch)
            if let id = vocab[key] {
                ids.append(id)
            } else {
                ids.append(BertSpeakerDetector.Config.unkTokenID)
            }
            if ids.count >= maxLength - 1 { break }
        }

        ids.append(BertSpeakerDetector.Config.sepTokenID)

        let mask = [Int32](repeating: 1, count: ids.count)

        // Pad
        while ids.count < maxLength {
            ids.append(BertSpeakerDetector.Config.padTokenID)
        }

        return (Array(ids[0..<maxLength]), mask + [Int32](repeating: 0, count: maxLength - mask.count))
    }

    private func loadVocab() {
        guard let url = Bundle.module.url(forResource: "vocab", withExtension: "txt") else {
            print("[BertTokenizer] vocab.txt not found")
            return
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        for (i, line) in content.components(separatedBy: "\n").enumerated() {
            let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                vocab[token] = Int32(i)
                idToToken[Int32(i)] = token
            }
        }
    }
}

// MARK: - Core ML input/output helper

fileprivate struct BertInput: MLFeatureProvider {
    let input_ids: MLMultiArray
    let attention_mask: MLMultiArray

    var featureNames: Set<String> { ["input_ids", "attention_mask"] }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "input_ids": return MLFeatureValue(multiArray: input_ids)
        case "attention_mask": return MLFeatureValue(multiArray: attention_mask)
        default: return nil
        }
    }
}
