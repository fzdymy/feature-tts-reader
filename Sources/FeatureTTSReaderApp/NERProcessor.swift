import Foundation
import NaturalLanguage
import CoreML

final class NERProcessor {
    private var customModel: MLModel?

    init() {
        if let modelURL = Bundle.module.url(forResource: "ChineseNER", withExtension: "mlmodelc") {
            customModel = try? MLModel(contentsOf: modelURL)
        }
    }

    var hasCustomModel: Bool { customModel != nil }

    func extractPersonNames(from text: String) -> OrderedSet<String> {
        if let model = customModel, let result = predictWithModel(model: model, text: text) {
            return OrderedSet(result)
        }
        var names = extractWithNL(text: text)
        let raw = text.replacingOccurrences(of: "\r", with: "\n")
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = raw
        tokenizer.enumerateTokens(in: raw.startIndex..<raw.endIndex) { range, _ in
            let token = String(raw[range])
            let cleaned = token.trimmingCharacters(in: .punctuationCharacters + .whitespaces)
            if cleaned.count >= 2 && cleaned.count <= 4 {
                let first = cleaned.unicodeScalars.first!
                if CharacterSet.ideographicCharacters.contains(first) {
                    let suffixChars = cleaned.dropFirst()
                    if suffixChars.allSatisfy({ CharacterSet.ideographicCharacters.contains($0.unicodeScalars.first!) }) {
                        if !cleaned.hasPrefix("第") && !cleaned.hasSuffix("章") && !cleaned.hasPrefix("不") && !cleaned.hasPrefix("这") && !cleaned.hasPrefix("那") && !cleaned.hasPrefix("什") {
                            names.append(cleaned)
                        }
                    }
                }
            }
            return true
        }
        return names
    }

    func detectSpeaker(from line: String, knownCharacters: [String]) -> String? {
        for name in knownCharacters {
            let prefix = "\(name)："
            if line.hasPrefix(name) || line.hasPrefix(prefix) {
                return name
            }
        }
        if let model = customModel, let predicted = predictWithModel(model: model, text: line) {
            for name in predicted {
                if knownCharacters.contains(name) { return name }
            }
            return predicted.first
        }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = line
        var detectedTag: String?
        tagger.enumerateTags(in: line.startIndex..<line.endIndex, unit: .word, scheme: .nameType, options: [.joinNames, .omitWhitespace, .omitOther]) { tag, range in
            if tag == .personalName {
                let name = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if knownCharacters.contains(name) {
                    detectedTag = name
                    return false
                }
                if detectedTag == nil { detectedTag = name }
            }
            return true
        }
        return detectedTag
    }
}

private func extractWithNL(text: String) -> OrderedSet<String> {
    var names = OrderedSet<String>()
    let tagger = NLTagger(tagSchemes: [.nameType])
    tagger.string = text
    tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.joinNames, .omitWhitespace, .omitOther]) { tag, range in
        if tag == .personalName {
            let name = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if name.count >= 2 && name.count <= 4 {
                names.append(name)
            }
        }
        return true
    }
    return names
}

private func predictWithModel(model: MLModel, text: String) -> [String]? {
    let inputDesc = model.modelDescription.inputDescriptionsByName
    guard let inputKey = inputDesc.keys.first,
          let inputConstraint = inputDesc[inputKey]?.multiArrayConstraint else {
        return nil
    }
    let shape = inputConstraint.shape.map { $0.intValue }
    guard shape.count >= 2, let seqLen = shape.last, seqLen > 0 else { return nil }
    do {
        let inputArray = try MLMultiArray(shape: [1, 1, NSNumber(value: seqLen)], dataType: .float32)
        let chars = Array(text.utf8)
        for i in 0..<min(chars.count, Int(seqLen)) {
            inputArray[[0, 0, NSNumber(value: i)]].floatValue = Float(chars[i]) / 255.0
        }
        let input = try MLDictionaryFeatureProvider(dictionary: [inputKey: inputArray])
        let output = try model.prediction(from: input)
        guard let outputKey = model.modelDescription.outputDescriptionsByName.keys.first,
              let outputArray = output.featureValue(for: outputKey)?.multiArrayValue else {
            return nil
        }
        var tagSequence: [Int32] = []
        for i in 0..<Int(seqLen) {
            tagSequence.append(outputArray[[0, 0, NSNumber(value: i)]].int32Value)
        }
        return decodeBIOTags(tagSequence, text: text)
    } catch {
        return nil
    }
}

private func decodeBIOTags(_ tags: [Int32], text: String) -> [String] {
    var entities: [String] = []
    var current: String = ""
    let chars = Array(text)
    for i in 0..<min(tags.count, chars.count) {
        if tags[i] == 1 || tags[i] == 2 {
            current.append(chars[i])
        } else {
            if !current.isEmpty {
                entities.append(current)
                current = ""
            }
        }
    }
    if !current.isEmpty { entities.append(current) }
    return entities.filter { $0.count >= 2 && $0.count <= 4 }
}

extension CharacterSet {
    static let ideographicCharacters: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "\u{4E00}"..."\u{9FFF}") // CJK Unified Ideographs
        set.insert(charactersIn: "\u{3400}"..."\u{4DBF}") // CJK Extension A
        set.insert(charactersIn: "\u{F900}"..."\u{FAFF}") // CJK Compatibility Ideographs
        return set
    }()
}
