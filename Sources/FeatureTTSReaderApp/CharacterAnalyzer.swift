import Foundation
import NaturalLanguage

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

struct DialogueMatch {
    let speaker: String?
    let content: String
    let range: Range<String.Index>
}

struct RelationshipEdge: Hashable {
    let source: String
    let target: String
    var weight: Int
}

final class CharacterAnalyzer {
    private let tokenizer = NLTokenizer(unit: .word)

    // MARK: - Name extraction (frequency + context + pattern)
    func extractNames(from text: String) -> [String] {
        let raw = text.replacingOccurrences(of: "\r", with: "\n")
        var scores = [String: Int]()

        // 1. Tokenizer-based candidate extraction with frequency
        tokenizer.string = raw
        var tokenFreq = [String: Int]()
        tokenizer.enumerateTokens(in: raw.startIndex..<raw.endIndex) { range, _ in
            let token = String(raw[range])
            let cleaned = token.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            if cleaned.count >= 2 && cleaned.count <= 4,
               cleaned.unicodeScalars.allSatisfy({ CharacterSet.ideographicCharacters.contains($0) }) {
                tokenFreq[cleaned, default: 0] += 1
            }
            return true
        }
        for (name, freq) in tokenFreq where freq >= 3 {
            if !isStopWord(name) {
                scores[name, default: 0] += min(freq, 100)
            }
        }

        // 2. Context regex patterns: XXX说/道/笑道/喊道/问道/怒道 etc
        let speechPatterns = [
            "([\\p{Han}]{2,4})(?=说[：:：])",
            "([\\p{Han}]{2,4})(?=道[：:：])",
            "([\\p{Han}]{2,4})(?=笑道[：:：])",
            "([\\p{Han}]{2,4})(?=喊道[：:：])",
            "([\\p{Han}]{2,4})(?=问道[：:：])",
            "([\\p{Han}]{2,4})(?=怒道[：:：])",
            "([\\p{Han}]{2,4})(?=哭道[：:：])",
            "([\\p{Han}]{2,4})(?=叹道[：:：])",
            "([\\p{Han}]{2,4})(?=轻声说[：:：])",
            "([\\p{Han}]{2,4})(?=低声道[：:：])",
            "([\\p{Han}]{2,4})(?=喃喃道[：:：])",
            "([\\p{Han}]{2,4})(?=大叫[：:：])",
            "([\\p{Han}]{2,4})(?=喝道[：:：])",
            "([\\p{Han}]{2,4})(?=骂[：:：])",
            "([\\p{Han}]{2,4})(?=问[：:：])",
            "([\\p{Han}]{2,4})(?=答[：:：])",
            "([\\p{Han}]{2,4})(?=應[：:：])",
        ]
        for pattern in speechPatterns {
            for match in raw.ranges(of: pattern) {
                let name = String(raw[match])
                if name.count >= 2 && name.count <= 4 {
                    scores[name, default: 0] += 15
                }
            }
        }

        // 3. Title patterns: XXX先生/小姐/姑娘/公子/师父/师傅/少爷/太太/夫人
        let titlePatterns = [
            "([\\p{Han}]{2,4})(?=先生|小姐|姑娘|公子|师父|师傅|少爷|太太|夫人|阁下|大人|兄台|贤弟|师妹|师姐|师兄|师弟)",
            "([\\p{Han}]{2,4})(?:先生|小姐|姑娘|公子|师父|师傅|少爷|太太|夫人|阁下|大人|兄台|贤弟)",
        ]
        for pattern in titlePatterns {
            for match in raw.ranges(of: pattern) {
                let name = String(raw[match])
                if name.count >= 2 && name.count <= 4 {
                    scores[name, default: 0] += 10
                }
            }
        }

        // 4. NLTagger personal name detection
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = raw
        tagger.enumerateTags(in: raw.startIndex..<raw.endIndex, unit: .word, scheme: .nameType, options: [.joinNames, .omitWhitespace, .omitOther]) { tag, range in
            if tag == .personalName {
                let name = String(raw[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if name.count >= 2 && name.count <= 4 {
                    scores[name, default: 0] += 20
                }
            }
            return true
        }

        // 5. Dialogue-based name detection: names before quoted speech
        let dialogueBeforePatterns = [
            "([\\p{Han}]{2,4})[：:\\s]*[「\\u201c\\u300c]",
            "([\\p{Han}]{2,4})[：:\\s]*[\"\\u201c]",
        ]
        for pattern in dialogueBeforePatterns {
            for match in raw.ranges(of: pattern) {
                let name = String(raw[match])
                    .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                    .replacingOccurrences(of: "：", with: "").replacingOccurrences(of: ":", with: "")
                if name.count >= 2 && name.count <= 4 {
                    scores[name, default: 0] += 10
                }
            }
        }

        // Filter and sort by score
        let minScore = 5
        let sorted = scores.filter { $0.value >= minScore }.sorted { $0.value > $1.value }
        return sorted.prefix(20).map(\.key)
    }

    // MARK: - Dialogue detection
    func detectDialogues(in text: String) -> [DialogueMatch] {
        var results: [DialogueMatch] = []

        let pattern = "[「\\u300c]([^」\\u300d]+)[」\\u300d]|[\"\\u201c]([^\"\\u201d]+)[\"\\u201d]"
        for match in text.ranges(of: pattern) {
            let segment = String(text[match])
            let content = segment
                .replacingOccurrences(of: "[「\\u300c]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[」\\u300d]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[\"\\u201c]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[\"\\u201d]", with: "", options: .regularExpression)

            let before = text[text.startIndex..<match.lowerBound]
            let speaker = inferSpeakerFromContext(String(before))
            results.append(DialogueMatch(speaker: speaker, content: content, range: match))
        }
        return results
    }

    private func inferSpeakerFromContext(_ precedingText: String) -> String? {
        let context = String(precedingText.suffix(60))
        let patterns = [
            "([\\p{Han}]{2,4})(?:说|道|笑道|喊道|问道|怒道|哭道|叹道|轻声说|低声道|喃喃道|大叫|喝道|骂|问|答|應)[：:]*$",
            "([\\p{Han}]{2,4})(?:先生|小姐|姑娘|公子|师父|师傅|少爷|太太|夫人)[：:]*$",
        ]
        for pattern in patterns {
            if let match = context.ranges(of: pattern).last {
                let name = String(context[match])
                    .replacingOccurrences(of: "[：:说笑道喊问道怒哭叹轻低喃大叫喝骂问答應]", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                if name.count >= 2 && name.count <= 4 { return name }
            }
        }
        return nil
    }

    // MARK: - Speaker inference
    func inferSpeaker(from line: String, knownCharacters: [String]) -> String? {
        for name in knownCharacters {
            if line.hasPrefix("\(name)：") || line.hasPrefix("\(name):") || line.hasPrefix("\(name)说") || line.hasPrefix("\(name)道") {
                return name
            }
        }
        for name in knownCharacters {
            if line.contains(name) {
                let context = line.prefix(40)
                let sayPatterns = ["说", "道", "笑道", "喊道", "问道", "怒道", "哭道", "叹道", "叫", "喝", "骂", "问", "答"]
                for p in sayPatterns {
                    if context.hasSuffix("\(name)\(p)") || context.hasSuffix("\(name)\(p)：") || context.hasSuffix("\(name)\(p):") {
                        return name
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Relationship graph (co-occurrence + dialogue)
    func buildRelationshipGraph(text: String, characterNames: [String]) -> [RelationshipEdge] {
        let nameSet = Set(characterNames)
        var cooccurrence: [String: [String: Int]] = [:]
        let paragraphs = text.components(separatedBy: "\n")

        // Paragraph-level co-occurrence
        for para in paragraphs where para.count < 2000 {
            let paraNames = extractNamesInParagraph(para, nameSet: nameSet)
            let sorted = paraNames.sorted()
            for i in 0..<sorted.count {
                for j in (i+1)..<sorted.count {
                    cooccurrence[sorted[i], default: [:]][sorted[j], default: 0] += 2
                }
            }
        }

        // Dialogue-based edges: who speaks to whom
        let dialogues = detectDialogues(in: text)
        for dialogue in dialogues {
            guard let speaker = dialogue.speaker, nameSet.contains(speaker) else { continue }
            for other in characterNames where other != speaker {
                if dialogue.content.contains(other) {
                    cooccurrence[speaker, default: [:]][other, default: 0] += 3
                    cooccurrence[other, default: [:]][speaker, default: 0] += 3
                }
            }
        }

        var edges: [RelationshipEdge] = []
        for (source, targets) in cooccurrence {
            for (target, weight) in targets {
                edges.append(RelationshipEdge(source: source, target: target, weight: weight))
            }
        }
        return edges.sorted { $0.weight > $1.weight }
    }

    private func extractNamesInParagraph(_ para: String, nameSet: Set<String>) -> Set<String> {
        var found: Set<String> = []
        tokenizer.string = para
        tokenizer.enumerateTokens(in: para.startIndex..<para.endIndex) { range, _ in
            let token = String(para[range])
            if nameSet.contains(token) { found.insert(token) }
            return true
        }
        return found
    }

    // MARK: - Frequency counting
    func countAppearances(text: String, characterNames: [String]) -> [(name: String, count: Int)] {
        let nameSet = Set(characterNames)
        var counts: [String: Int] = [:]
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range])
            if nameSet.contains(token) { counts[token, default: 0] += 1 }
            return true
        }
        return characterNames.map { ($0, counts[$0] ?? 0) }
    }

    // MARK: - Attribute analysis
    func analyzeAttributes(for name: String, context: String) -> CharacterAttributes {
        let gender = inferGender(from: context)
        let age = inferAge(from: context)
        let tone = inferBaseTone(from: context)
        let style = styleFromToneName(tone)
        let rate = tone == "激昂" ? 15 : tone == "温柔" ? -10 : tone == "轻松" ? 5 : 0
        let pitch = tone == "激昂" ? 10 : tone == "温柔" ? -5 : tone == "疑问" ? 5 : 0
        return CharacterAttributes(gender: gender, age: age, baseTone: tone, baseStyle: style, baseRate: rate, basePitch: pitch)
    }

    func analyzeSentenceTone(_ line: String) -> ToneResult {
        if line.contains("！") && !line.contains("？") {
            for w in ["怒", "愤", "恨", "吼", "骂", "怒道", "喝道"] where line.contains(w) {
                return ToneResult(style: "angry", pitchAdjust: 12, rateAdjust: 10)
            }
            return ToneResult(style: "cheerful", pitchAdjust: 8, rateAdjust: 5)
        }
        if line.contains("？") || line.contains("?") {
            return ToneResult(style: "neutral", pitchAdjust: 5, rateAdjust: 0)
        }
        for w in ["叹", "悲", "哭", "哀", "泣", "叹道", "哭道", "轻声", "低声"] where line.contains(w) {
            return ToneResult(style: "sad", pitchAdjust: -8, rateAdjust: -8)
        }
        return ToneResult(style: "neutral", pitchAdjust: 0, rateAdjust: 0)
    }

    // MARK: - Private helpers
    private func inferGender(from context: String) -> String {
        let ctx = context
        if ctx.contains("小姐") || ctx.contains("姑娘") || ctx.contains("她") || ctx.contains("母亲") ||
           ctx.contains("姐姐") || ctx.contains("妹妹") || ctx.contains("老婆") || ctx.contains("太太") ||
           ctx.contains("闺女") || ctx.contains("妇人") || ctx.contains("婶婶") || ctx.contains("奶奶") ||
           ctx.contains("姥姥") || ctx.contains("女士") || ctx.contains("女儿") || ctx.contains("公主") ||
           ctx.contains("贵妃") || ctx.contains("皇后") || ctx.contains("太后") || ctx.contains("女侠") ||
           ctx.contains("少女") || ctx.contains("女童") || ctx.contains("师妹") || ctx.contains("师姐") {
            return "女性"
        }
        if ctx.contains("先生") || ctx.contains("公子") || ctx.contains("哥哥") || ctx.contains("弟弟") ||
           ctx.contains("丈夫") || ctx.contains("小伙") || ctx.contains("大叔") || ctx.contains("大爷") ||
           ctx.contains("伯伯") || ctx.contains("叔叔") || ctx.contains("少爷") || ctx.contains("儿子") ||
           ctx.contains("他") || ctx.contains("兄弟") || ctx.contains("陛下") || ctx.contains("王爷") ||
           ctx.contains("将军") || ctx.contains("丞相") || ctx.contains("兄台") || ctx.contains("贤弟") ||
           ctx.contains("师兄") || ctx.contains("师弟") || ctx.contains("道长") {
            return "男性"
        }
        return "未知"
    }

    private func inferAge(from context: String) -> String {
        if context.contains("小孩") || context.contains("孩子") || context.contains("孩童") || context.contains("幼") || context.contains("小儿") || context.contains("小童") {
            return "少年"
        }
        if context.contains("少女") || context.contains("小姐") || context.contains("姑娘") || context.contains("女童") || context.contains("女侠") {
            return "少女"
        }
        if context.contains("少年") || context.contains("青年") || context.contains("年轻") || context.contains("小伙") {
            return "青年"
        }
        if context.contains("中年") || context.contains("师傅") || context.contains("大人") || context.contains("师父") {
            return "中年"
        }
        if context.contains("年迈") || context.contains("老太") || context.contains("老人") || context.contains("老翁") || context.contains("老者") || context.contains("老年") || context.contains("婆婆") {
            return "年长"
        }
        return "未知"
    }

    private func inferBaseTone(from context: String) -> String {
        var scores = [String: Int]()
        if context.contains("！") { scores["激昂", default: 0] += 2 }
        for w in ["怒", "愤", "恨", "吼", "骂", "怒道", "喝道", "暴躁", "冷声道"] { scores["激昂", default: 0] += 2 }
        for w in ["叹", "悲", "哀", "泣", "叹道", "哭道", "轻声", "低声", "温柔", "轻声说", "柔和"] { scores["温柔", default: 0] += 2 }
        for w in ["笑", "喜", "欢", "乐", "开心", "笑道", "莞尔", "轻松", "玩笑"] { scores["轻松", default: 0] += 2 }
        if context.contains("？") || context.contains("?") { scores["疑问", default: 0] += 1 }
        if let max = scores.max(by: { $0.value < $1.value }), max.value > 0 { return max.key }
        return "平稳"
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

    private func isStopWord(_ word: String) -> Bool {
        let stops = ["第一", "第二", "第三", "第十", "最后", "开始", "结束", "不过", "突然", "然后", "但是", "因为", "所以", "虽然", "如果", "可是", "只是", "就是", "还是", "这个", "那个", "什么", "怎么", "这样", "那样", "这些", "那些", "这里", "那里", "时候", "以后", "之前", "没有", "不是", "自己", "他们", "她们", "你们", "我们", "大家", "一切", "一个", "一种", "别的", "各自", "对面", "眼前", "面前", "身后", "背后", "手中", "脚下", "天上", "地下", "心中", "脸上", "眼里", "嘴里", "身上", "头上", "手中", "脚下", "晚上", "上午", "下午", "方才", "刚才", "此刻", "现在", "原来", "本来", "起来", "出来", "过来", "回来", "进去", "出去", "看见", "看到", "听见", "听到", "知道", "觉得", "感觉", "有点", "有些", "十分", "非常", "特别", "更加", "稍微", "轻轻", "慢慢", "渐渐", "终于", "从未", "从未", "已然", "尚未", "已经", "曾经", "就要", "就要", "还是", "就是", "只是", "可是", "但是", "因为", "所以", "虽然", "如果", "不过", "而且", "并且", "或者", "还是", "不但", "不仅", "甚至", "连同", "以及"]
        return stops.contains(word) || word.hasPrefix("第") || word.hasSuffix("章") || word.hasPrefix("不") || word.hasPrefix("这") || word.hasPrefix("那") || word.hasPrefix("什") || word.hasPrefix("我") || word.hasPrefix("你")
    }
}

extension CharacterSet {
    static let ideographicCharacters: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: UnicodeScalar(UInt32(0x4E00))!..<UnicodeScalar(UInt32(0xA000))!)
        set.insert(charactersIn: UnicodeScalar(UInt32(0x3400))!..<UnicodeScalar(UInt32(0x4DC0))!)
        set.insert(charactersIn: UnicodeScalar(UInt32(0xF900))!..<UnicodeScalar(UInt32(0xFB00))!)
        return set
    }()
}

// MARK: - Regex helpers
extension String {
    func ranges(of pattern: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, options: [], range: nsRange).compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            let gr = match.range(at: 1)
            return Range(gr, in: self)
        }
    }
}
