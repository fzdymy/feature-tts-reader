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

    // MARK: - Name extraction (tokenizer frequency + context + bigram merging)
    func extractNames(from text: String) -> [String] {
        let raw = text.replacingOccurrences(of: "\r", with: "\n")
        var scores = [String: Int]()

        // 1. Tokenizer-based candidate extraction with frequency
        tokenizer.string = raw
        var tokenFreq = [String: Int]()
        var tokenPositions: [(String, Int)] = []
        var position = 0
        tokenizer.enumerateTokens(in: raw.startIndex..<raw.endIndex) { range, _ in
            let token = String(raw[range])
            let cleaned = token.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            if cleaned.count >= 2 && cleaned.count <= 4,
               cleaned.unicodeScalars.allSatisfy({ CharacterSet.ideographicCharacters.contains($0) }) {
                tokenFreq[cleaned, default: 0] += 1
                tokenPositions.append((cleaned, position))
            }
            position += 1
            return true
        }
        for (name, freq) in tokenFreq where freq >= 2 {
            if !isStopWord(name) {
                scores[name, default: 0] += min(freq, 100)
            }
        }

        // 1b. Bigram merging: merge adjacent 2-char tokens into 4-char candidate names
        var bigramFreq = [String: Int]()
        for i in 0..<(tokenPositions.count - 1) {
            let (a, posA) = tokenPositions[i]
            let (b, posB) = tokenPositions[i + 1]
            if posA + 1 == posB && a.count == 2 && b.count == 2 {
                let merged = a + b
                if merged.unicodeScalars.allSatisfy({ CharacterSet.ideographicCharacters.contains($0) }),
                   !isStopWord(merged) {
                    bigramFreq[merged, default: 0] += 1
                }
            }
        }
        for (name, freq) in bigramFreq where freq >= 2 {
            scores[name, default: 0] += min(freq * 15, 100)
        }

        // 2. Context regex patterns covering more speech verbs
        let speechVerbs = "说|道|笑道|喊道|问道|怒道|哭道|叹道|骂道|喝道|叫道|低声道|轻声道|柔声道|冷声道|颤声道|沉声道|厉声道|正色道|正色说|接话道|插嘴道|接口道|应声道|抢先道|解释道|回答|追问|吩咐|叮嘱|嘱咐|呵斥|训斥|呵道"
        for match in raw.ranges(of: "([\\p{Han}]{2,4})\(speechVerbs)") {
            let name = String(raw[match])
            if name.count >= 2 && name.count <= 4 {
                scores[name, default: 0] += 15
            }
        }

        // 3. Title patterns
        let titles = "先生|小姐|姑娘|公子|师父|师傅|少爷|太太|夫人|阁下|大人|兄台|贤弟|师妹|师姐|师兄|师弟|掌门|教主|帮主|盟主|庄主|岛主|前辈|姑娘|婆婆|姥姥|老爷子|老人家"
        for match in raw.ranges(of: "([\\p{Han}]{2,4})(?=\(titles))") {
            let name = String(raw[match])
            if name.count >= 2 && name.count <= 4 {
                scores[name, default: 0] += 12
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

        // 5. Dialogue-based name detection (before quotes)
        for match in raw.ranges(of: "([\\p{Han}]{2,4})[：:\\s]*[「\\u300c\\u201c]") {
            let rawName = String(raw[match])
            let name = rawName.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                .replacingOccurrences(of: "：", with: "").replacingOccurrences(of: ":", with: "")
            if name.count >= 2 && name.count <= 4 {
                scores[name, default: 0] += 10
            }
        }

        // 6. Chapter title names: first 2-4 Han of chapter title lines
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 2 && trimmed.count <= 15 {
                let digits = "第[一二三四五六七八九十百千零\\d]+[章回节]"
                if let _ = try? NSRegularExpression(pattern: "^\(digits).*").firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)) {
                    let cleaned = trimmed
                        .replacingOccurrences(of: "^\(digits)", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                    if cleaned.count >= 2 && cleaned.count <= 4 {
                        scores[cleaned, default: 0] += 5
                    }
                }
            }
        }

        // Filter and sort by score
        let minScore = 6
        let sorted = scores.filter { $0.value >= minScore }.sorted { $0.value > $1.value }
        return sorted.prefix(30).map(\.key)
    }

    // MARK: - Dialogue detection
    func detectDialogues(in text: String) -> [DialogueMatch] {
        var results: [DialogueMatch] = []
        var lastKnownSpeaker: String?

        let quotePatterns = [
            "[「\\u300c]([^」\\u300d]+)[」\\u300d]",
            "['\\u2018]([^'\\u2019]+)['\\u2019]",
            "[\"\\u201c]([^\"\\u201d]+)[\"\\u201d]",
            "[『\\u300e]([^』\\u300f]+)[』\\u300f]",
        ]
        for pattern in quotePatterns {
            for match in text.ranges(of: pattern) {
                guard match.lowerBound >= text.startIndex else { continue }
                let segment = String(text[match])
                let content = segment
                    .replacingOccurrences(of: "^[「\\u300c'\\u2018\"\\u201c『\\u300e]", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "[」\\u300d'\\u2019\"\\u201d』\\u300f]$", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if content.isEmpty { continue }

                let before = text[text.startIndex..<match.lowerBound]
                if let speaker = inferSpeakerFromContext(String(before)) {
                    lastKnownSpeaker = speaker
                }
                results.append(DialogueMatch(speaker: lastKnownSpeaker, content: content, range: match))
            }
        }
        return results
    }

    private func inferSpeakerFromContext(_ precedingText: String) -> String? {
        let context = String(precedingText.suffix(100))
        let speechVerbs = "说|道|笑道|喊道|问道|怒道|哭道|叹道|骂道|喝道|叫道|低声道|轻声道|柔声道|冷声道|颤声道|沉声道|厉声道|正色道|接话道|插嘴道|接口道|应声道|抢先道|解释道|回答|追问|吩咐|叮嘱|嘱咐|呵斥|训斥|呵道"
        // "XXX说/道/etc" followed by optional colon at end of preceding text
        if let match = context.ranges(of: "([\\p{Han}]{2,4})(?:\(speechVerbs))[：:]*$").last {
            let raw = String(context[match])
            let name = raw
                .replacingOccurrences(of: "(?:\(speechVerbs))[：:]*$", with: "", options: .regularExpression)
                .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            if name.count >= 2 && name.count <= 4 { return name }
        }
        // "XXX" followed by title suffix at end of preceding text
        if let match = context.ranges(of: "([\\p{Han}]{2,4})(?:先生|小姐|姑娘|公子|师父|师傅|少爷|太太|夫人|阁下|大人|前辈|掌门|教主)[：:]*$").last {
            let raw = String(context[match])
            let name = raw
                .replacingOccurrences(of: "(?:先生|小姐|姑娘|公子|师父|师傅|少爷|太太|夫人|阁下|大人|前辈|掌门|教主)[：:]*$", with: "", options: .regularExpression)
                .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            if name.count >= 2 && name.count <= 4 { return name }
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

        // Paragraph-level co-occurrence with sliding window
        for para in paragraphs where para.count < 2000 {
            let paraNames = extractNamesInParagraph(para, nameSet: nameSet).sorted()
            if paraNames.count >= 2 {
                let windowSize = 100
                var pos = para.startIndex
                while pos < para.endIndex {
                    let end = para.index(pos, offsetBy: windowSize, limitedBy: para.endIndex) ?? para.endIndex
                    let window = String(para[pos..<end])
                    let windowNames = extractNamesInParagraph(window, nameSet: nameSet).sorted()
                    for i in 0..<windowNames.count {
                        for j in (i+1)..<windowNames.count {
                            cooccurrence[windowNames[i], default: [:]][windowNames[j], default: 0] += 3
                            cooccurrence[windowNames[j], default: [:]][windowNames[i], default: 0] += 3
                        }
                    }
                    pos = para.index(pos, offsetBy: max(1, para.distance(from: pos, to: end) / 2), limitedBy: para.endIndex) ?? para.endIndex
                }
            }
            for i in 0..<paraNames.count {
                for j in (i+1)..<paraNames.count {
                    cooccurrence[paraNames[i], default: [:]][paraNames[j], default: 0] += 1
                    cooccurrence[paraNames[j], default: [:]][paraNames[i], default: 0] += 1
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
        let angryWords = ["怒", "愤", "恨", "吼", "骂", "怒道", "喝道", "呵斥", "训斥", "喝道", "怒喝"]
        let sadWords = ["叹", "悲", "哭", "哀", "泣", "叹道", "哭道", "轻声", "低声", "哽咽", "啜泣", "悲伤", "凄凉"]
        let cheerfulWords = ["笑", "喜", "欢", "乐", "开心", "笑道", "莞尔", "玩笑", "高兴"]

        if line.contains("！") && !line.contains("？") {
            for w in angryWords where line.contains(w) {
                return ToneResult(style: "angry", pitchAdjust: 12, rateAdjust: 10)
            }
            for w in cheerfulWords where line.contains(w) {
                return ToneResult(style: "cheerful", pitchAdjust: 8, rateAdjust: 5)
            }
            return ToneResult(style: "cheerful", pitchAdjust: 8, rateAdjust: 5)
        }
        if line.contains("？") || line.contains("?") {
            return ToneResult(style: "neutral", pitchAdjust: 5, rateAdjust: 0)
        }
        for w in angryWords where line.contains(w) {
            return ToneResult(style: "angry", pitchAdjust: 12, rateAdjust: 10)
        }
        for w in sadWords where line.contains(w) {
            return ToneResult(style: "sad", pitchAdjust: -8, rateAdjust: -8)
        }
        for w in cheerfulWords where line.contains(w) {
            return ToneResult(style: "cheerful", pitchAdjust: 8, rateAdjust: 5)
        }
        return ToneResult(style: "neutral", pitchAdjust: 0, rateAdjust: 0)
    }

    // MARK: - Private helpers
    private func inferGender(from context: String) -> String {
        if context.contains("她") || context.contains("母亲") || context.contains("娘") ||
           context.contains("小姐") || context.contains("姑娘") || context.contains("姐姐") ||
           context.contains("妹妹") || context.contains("老婆") || context.contains("太太") ||
           context.contains("闺女") || context.contains("妇人") || context.contains("婶婶") ||
           context.contains("奶奶") || context.contains("姥姥") || context.contains("女士") ||
           context.contains("女儿") || context.contains("公主") || context.contains("贵妃") ||
           context.contains("皇后") || context.contains("太后") || context.contains("女侠") ||
           context.contains("少女") || context.contains("女童") || context.contains("师妹") ||
           context.contains("师姐") || context.contains("女眷") || context.contains("女子") ||
           context.contains("女人") || context.contains("母") {
            return "女性"
        }
        if context.contains("他") || context.contains("先生") || context.contains("公子") ||
           context.contains("哥哥") || context.contains("弟弟") || context.contains("丈夫") ||
           context.contains("小伙") || context.contains("大叔") || context.contains("大爷") ||
           context.contains("伯伯") || context.contains("叔叔") || context.contains("少爷") ||
           context.contains("儿子") || context.contains("兄弟") || context.contains("陛下") ||
           context.contains("王爷") || context.contains("将军") || context.contains("丞相") ||
           context.contains("兄台") || context.contains("贤弟") || context.contains("师兄") ||
           context.contains("师弟") || context.contains("道长") || context.contains("掌门") ||
           context.contains("教主") || context.contains("帮主") || context.contains("庄主") ||
           context.contains("男人") || context.contains("男子") || context.contains("汉子") ||
           context.contains("父") || context.contains("爹") || context.contains("爷") {
            return "男性"
        }
        return "未知"
    }

    private func inferAge(from context: String) -> String {
        if context.contains("小孩") || context.contains("孩子") || context.contains("孩童") ||
           context.contains("幼") || context.contains("小儿") || context.contains("小童") ||
           context.contains("婴儿") || context.contains("儿童") || context.contains("娃娃") {
            return "少年"
        }
        if context.contains("少女") || context.contains("小姐") || context.contains("姑娘") ||
           context.contains("女童") || context.contains("女侠") || context.contains("丫头") ||
           context.contains("丫鬟") || context.contains("侍婢") || context.contains("侍女") {
            return "少女"
        }
        if context.contains("少年") || context.contains("青年") || context.contains("年轻") ||
           context.contains("小伙") || context.contains("公子") || context.contains("少侠") {
            return "青年"
        }
        if context.contains("中年") || context.contains("师傅") || context.contains("大人") ||
           context.contains("师父") || context.contains("大叔") || context.contains("伯伯") ||
           context.contains("叔叔") || context.contains("婶婶") || context.contains("夫人") ||
           context.contains("太太") || context.contains("妇人") {
            return "中年"
        }
        if context.contains("年迈") || context.contains("老太") || context.contains("老人") ||
           context.contains("老翁") || context.contains("老者") || context.contains("老年") ||
           context.contains("婆婆") || context.contains("姥姥") || context.contains("奶奶") ||
           context.contains("大爷") || context.contains("老爷子") || context.contains("老人家") {
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
        let stops = Set(["第一", "第二", "第三", "第四", "第五", "第十", "最后", "开始", "结束", "不过", "突然", "然后", "但是", "因为", "所以", "虽然", "如果", "可是", "只是", "就是", "还是", "这个", "那个", "什么", "怎么", "这样", "那样", "这些", "那些", "这里", "那里", "时候", "以后", "之前", "没有", "不是", "自己", "他们", "她们", "你们", "我们", "大家", "一切", "一个", "一种", "别的", "各自", "对面", "眼前", "面前", "身后", "背后", "手中", "脚下", "天上", "地下", "心中", "脸上", "眼里", "嘴里", "身上", "头上", "晚上", "上午", "下午", "方才", "刚才", "此刻", "现在", "原来", "本来", "起来", "出来", "过来", "回来", "进去", "出去", "看见", "看到", "听见", "听到", "知道", "觉得", "感觉", "有点", "有些", "十分", "非常", "特别", "更加", "稍微", "轻轻", "慢慢", "渐渐", "终于", "从未", "已然", "尚未", "已经", "曾经", "就要", "还是", "就是", "只是", "可是", "但是", "因为", "所以", "虽然", "如果", "不过", "而且", "并且", "或者", "不但", "不仅", "甚至", "连同", "以及", "全都", "全部", "凡是", "各位", "诸位", "自从", "由于", "关于", "对于", "根据"])
        return stops.contains(word) || word.hasPrefix("第") || word.hasSuffix("章") || word.hasSuffix("回") || word.hasSuffix("节") || word.hasPrefix("这") || word.hasPrefix("那") || word.hasPrefix("什") || word.hasPrefix("我") || word.hasPrefix("你")
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
