import Foundation
import NaturalLanguage
import CoreML

// MARK: - Protocols for pluggable inference models
protocol NERModel {
    func extractNames(from text: String) -> [String]
    func inferSpeaker(from line: String, knownCharacters: [String]) -> String?
    func analyzeAttributes(for name: String, context: String) -> CharacterAttributes
    func analyzeSentenceTone(_ line: String) -> ToneResult
}

struct CharacterAttributes {
    var gender: String
    var age: String
    var baseTone: String
    var baseStyle: String
    var baseRate: Int
    var basePitch: Int
}

struct ToneResult {
    var style: String
    var pitchAdjust: Int
    var rateAdjust: Int
}

// MARK: - Default analyzer using NaturalLanguage + keyword heuristics
final class NLCharacterAnalyzer: NERModel {
    func extractNames(from text: String) -> [String] {
        let raw = text.replacingOccurrences(of: "\r", with: "\n")
        var names = OrderedSet<String>()

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = raw
        tagger.enumerateTags(in: raw.startIndex..<raw.endIndex, unit: .word, scheme: .nameType, options: [.joinNames, .omitWhitespace, .omitOther]) { tag, range in
            if tag == .personalName {
                let name = String(raw[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if name.count >= 2 && name.count <= 4 {
                    names.append(name)
                }
            }
            return true
        }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = raw
        tokenizer.enumerateTokens(in: raw.startIndex..<raw.endIndex) { range, _ in
            let token = String(raw[range])
            let cleaned = token.trimmingCharacters(in: .punctuationCharacters + .whitespaces)
            if cleaned.count >= 2 && cleaned.count <= 4 {
                if cleaned.unicodeScalars.allSatisfy({ CharacterSet.ideographicCharacters.contains($0) }) {
                    if !cleaned.hasPrefix("第") && !cleaned.hasSuffix("章") && !cleaned.hasPrefix("不") && !cleaned.hasPrefix("这") && !cleaned.hasPrefix("那") && !cleaned.hasPrefix("什") {
                        names.append(cleaned)
                    }
                }
            }
            return true
        }

        return Array(names)
    }

    func inferSpeaker(from line: String, knownCharacters: [String]) -> String? {
        for name in knownCharacters {
            if line.hasPrefix("\(name)：") || line.hasPrefix("\(name):") || line.hasPrefix(name) {
                return name
            }
        }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = line
        var detected: String?
        tagger.enumerateTags(in: line.startIndex..<line.endIndex, unit: .word, scheme: .nameType, options: [.joinNames, .omitWhitespace, .omitOther]) { tag, range in
            if tag == .personalName {
                let name = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if knownCharacters.contains(name) {
                    detected = name
                    return false
                }
                if detected == nil { detected = name }
            }
            return true
        }
        return detected
    }

    func analyzeAttributes(for name: String, context: String) -> CharacterAttributes {
        let gender = inferGender(from: context)
        let age = inferAge(from: context)
        let tone = inferBaseTone(from: context)
        let style = styleFromToneName(tone)
        let rate = tone == "激昂" ? 15 : tone == "温柔" ? -10 : tone == "轻松" ? 5 : 0
        let pitch = tone == "激昂" ? 10 : tone == "温柔" ? -5 : tone == "疑问" ? 5 : 0
        return CharacterAttributes(
            gender: gender, age: age, baseTone: tone,
            baseStyle: style, baseRate: rate, basePitch: pitch
        )
    }

    func analyzeSentenceTone(_ line: String) -> ToneResult {
        var excitement = 0
        if line.contains("！") { excitement += 2 }
        if line.contains("?") || line.contains("？") { excitement += 1 }
        for word in ["怒", "愤", "恨", "骂", "吼", "怒道", "喝道"] {
            if line.contains(word) { excitement += 2; break }
        }
        if excitement >= 3 {
            return ToneResult(style: "angry", pitchAdjust: 12, rateAdjust: 10)
        }
        for word in ["笑", "喜", "欢", "乐", "开心", "笑道", "莞尔"] {
            if line.contains(word) { excitement += 1; break }
        }
        if line.contains("！") && !line.contains("？") {
            return ToneResult(style: "cheerful", pitchAdjust: 8, rateAdjust: 5)
        }
        if line.contains("？") || line.contains("?") {
            return ToneResult(style: "neutral", pitchAdjust: 5, rateAdjust: 0)
        }
        for word in ["叹", "悲", "哭", "哀", "泣", "叹道", "哭道", "轻声", "低声"] {
            if line.contains(word) { return ToneResult(style: "sad", pitchAdjust: -8, rateAdjust: -8) }
        }
        return ToneResult(style: "neutral", pitchAdjust: 0, rateAdjust: 0)
    }

    private func inferGender(from context: String) -> String {
        let ctx = context
        if ctx.contains("小姐") || ctx.contains("姑娘") || ctx.contains("她") || ctx.contains("母亲") || ctx.contains("姐姐") || ctx.contains("妹妹") || ctx.contains("老婆") || ctx.contains("太太") || ctx.contains("闺女") || ctx.contains("妇人") || ctx.contains("婶婶") || ctx.contains("奶奶") || ctx.contains("姥姥") || ctx.contains("女士") || ctx.contains("女儿") {
            return "女性"
        }
        if ctx.contains("先生") || ctx.contains("公子") || ctx.contains("哥哥") || ctx.contains("弟弟") || ctx.contains("丈夫") || ctx.contains("小伙") || ctx.contains("大叔") || ctx.contains("大爷") || ctx.contains("伯伯") || ctx.contains("叔叔") || ctx.contains("少爷") || ctx.contains("儿子") || ctx.contains("他") {
            return "男性"
        }
        return "未知"
    }

    private func inferAge(from context: String) -> String {
        if context.contains("小孩") || context.contains("稚") || context.contains("孩子") || context.contains("孩童") || context.contains("幼") || context.contains("小儿") {
            return "少年"
        }
        if context.contains("少女") || context.contains("小姐") || context.contains("姑娘") || context.contains("女童") {
            return "少女"
        }
        if context.contains("少年") || context.contains("青年") || context.contains("年轻") || context.contains("小伙") || (context.contains("少") && !context.contains("多少") && !context.contains("不少")) {
            return "青年"
        }
        if context.contains("中年") || context.contains("师傅") || context.contains("大人") {
            return "中年"
        }
        if context.contains("年迈") || context.contains("老太") || context.contains("老人") || context.contains("老翁") || context.contains("老者") || context.contains("老年") {
            return "年长"
        }
        return "未知"
    }

    private func inferBaseTone(from context: String) -> String {
        var scores = [String: Int]()
        if context.contains("！") { scores["激昂", default: 0] += 2 }
        for w in ["怒", "愤", "恨", "吼", "骂", "怒道", "喝道"] {
            if context.contains(w) { scores["激昂", default: 0] += 2 }
        }
        for w in ["叹", "悲", "哀", "泣", "叹道", "轻声", "低声", "温柔", "轻声说"] {
            if context.contains(w) { scores["温柔", default: 0] += 2 }
        }
        for w in ["笑", "喜", "欢", "乐", "开心", "笑道", "莞尔", "轻松"] {
            if context.contains(w) { scores["轻松", default: 0] += 2 }
        }
        if context.contains("？") || context.contains("?") {
            scores["疑问", default: 0] += 1
        }
        if let max = scores.max(by: { $0.value < $1.value }), max.value > 0 {
            return max.key
        }
        return "平稳"
    }
}

private func styleFromToneName(_ tone: String) -> String {
    switch tone {
    case "激昂": return "angry"
    case "疑问": return "neutral"
    case "温柔": return "sad"
    case "轻松": return "cheerful"
    default: return "neutral"
    }
}

// MARK: - Core ML model wrapper
final class CoreMLCharacterAnalyzer: NERModel {
    private var model: MLModel?
    private let fallback = NLCharacterAnalyzer()

    init() {
        if let url = Bundle.module.url(forResource: "ChineseNER", withExtension: "mlmodelc") {
            model = try? MLModel(contentsOf: url)
        }
    }

    var isAvailable: Bool { model != nil }

    func extractNames(from text: String) -> [String] {
        guard let m = model, let predicted = predict(m, text: text) else {
            return fallback.extractNames(from: text)
        }
        return predicted
    }

    func inferSpeaker(from line: String, knownCharacters: [String]) -> String? {
        guard let m = model, let names = predict(m, text: line) else {
            return fallback.inferSpeaker(from: line, knownCharacters: knownCharacters)
        }
        for name in names {
            if knownCharacters.contains(name) { return name }
        }
        return names.first
    }

    func analyzeAttributes(for name: String, context: String) -> CharacterAttributes {
        fallback.analyzeAttributes(for: name, context: context)
    }

    func analyzeSentenceTone(_ line: String) -> ToneResult {
        fallback.analyzeSentenceTone(line)
    }

    private func predict(_ m: MLModel, text: String) -> [String]? {
        let desc = m.modelDescription
        guard let inputKey = desc.inputDescriptionsByName.keys.first else { return nil }
        let inputDesc = desc.inputDescriptionsByName[inputKey]!
        guard let constraint = inputDesc.multiArrayConstraint else { return nil }
        let shape = constraint.shape.map { $0.intValue }
        guard shape.count >= 2, let seqLen = shape.last, seqLen > 50 else { return nil }
        do {
            let arr = try MLMultiArray(shape: [1, 1, NSNumber(value: seqLen)], dataType: .float32)
            let chars = Array(text.utf8)
            for i in 0..<min(chars.count, Int(seqLen)) {
                arr[[0, 0, NSNumber(value: i)]] = NSNumber(value: Float(chars[i]) / 255.0)
            }
            let input = try MLDictionaryFeatureProvider(dictionary: [inputKey: arr])
            let output = try m.prediction(from: input)
            guard let outKey = desc.outputDescriptionsByName.keys.first,
                  let outArr = output.featureValue(for: outKey)?.multiArrayValue else { return nil }
            var tags: [Int32] = []
            for i in 0..<Int(seqLen) {
                tags.append(outArr[[0, 0, NSNumber(value: i)]].int32Value)
            }
            return decodeBIOTags(tags, text: text)
        } catch {
            return nil
        }
    }
}

private func decodeBIOTags(_ tags: [Int32], text: String) -> [String] {
    var entities: [String] = []
    var current = ""
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

// MARK: - Facade combining both analyzers
final class CharacterAnalyzer {
    private let coreML: CoreMLCharacterAnalyzer
    private let defaultAnalyzer: NERModel

    init() {
        let ml = CoreMLCharacterAnalyzer()
        coreML = ml
        defaultAnalyzer = ml.isAvailable ? ml : NLCharacterAnalyzer()
    }

    var usingCoreML: Bool { coreML.isAvailable }

    private var analyzer: NERModel { defaultAnalyzer }

    func extractNames(from text: String) -> [String] {
        analyzer.extractNames(from: text)
    }

    func inferSpeaker(from line: String, knownCharacters: [String]) -> String? {
        analyzer.inferSpeaker(from: line, knownCharacters: knownCharacters)
    }

    func analyzeAttributes(for name: String, context: String) -> CharacterAttributes {
        analyzer.analyzeAttributes(for: name, context: context)
    }

    func analyzeSentenceTone(_ line: String) -> ToneResult {
        analyzer.analyzeSentenceTone(line)
    }
}

extension CharacterSet {
    static let ideographicCharacters: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: UnicodeScalar(0x4E00)...UnicodeScalar(0x9FFF))
        set.insert(charactersIn: UnicodeScalar(0x3400)...UnicodeScalar(0x4DBF))
        set.insert(charactersIn: UnicodeScalar(0xF900)...UnicodeScalar(0xFAFF))
        return set
    }()
}
