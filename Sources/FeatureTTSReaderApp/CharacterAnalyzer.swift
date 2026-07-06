import Foundation
import NaturalLanguage

// MARK: - Data Types

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

// MARK: - Regex Cache

private final class RegexCache: @unchecked Sendable {
    static let shared = RegexCache()
    private var cache: [String: NSRegularExpression] = [:]
    private let lock = NSLock()

    func get(_ pattern: String) -> NSRegularExpression? {
        lock.lock(); defer { lock.unlock() }
        if let re = cache[pattern] { return re }
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        cache[pattern] = re
        return re
    }
}

// MARK: - Aho-Corasick Automaton

final class ACAutomaton {
    private class Node {
        var children: [Character: Node] = [:]
        var fail: Node?
        var output: [String] = []
    }

    private var root = Node()
    private var built = false

    func insert(_ pattern: String) {
        var node = root
        for ch in pattern {
            if let child = node.children[ch] {
                node = child
            } else {
                let child = Node()
                node.children[ch] = child
                node = child
            }
        }
        node.output.append(pattern)
        built = false
    }

    func build() {
        var queue: [Node] = []
        for (_, child) in root.children {
            child.fail = root
            queue.append(child)
        }
        while !queue.isEmpty {
            let node = queue.removeFirst()
            for (ch, child) in node.children {
                var fail = node.fail
                while fail != nil && fail!.children[ch] == nil {
                    fail = fail!.fail
                }
                child.fail = (fail?.children[ch]) ?? root
                child.output.append(contentsOf: child.fail?.output ?? [])
                queue.append(child)
            }
        }
        built = true
    }

    func search(_ text: String) -> [String: Int] {
        if !built { build() }
        var counts: [String: Int] = [:]
        var node = root
        for ch in text {
            while node !== root && node.children[ch] == nil {
                node = node.fail ?? root
            }
            if let child = node.children[ch] {
                node = child
            }
            for pattern in node.output {
                counts[pattern, default: 0] += 1
            }
        }
        return counts
    }
}

// MARK: - CharacterAnalyzer

final class CharacterAnalyzer: @unchecked Sendable {
    private let tokenizer: NLTokenizer = {
        let t = NLTokenizer(unit: .word)
        return t
    }()

    static let titleSuffixes: Set<String> = [
        "先生", "小姐", "姑娘", "公子", "师父", "师傅", "少爷", "太太",
        "夫人", "阁下", "大人", "前辈", "掌门", "教主", "帮主", "盟主",
        "庄主", "岛主", "兄台", "贤弟", "师妹", "师姐", "师兄", "师弟",
        "婆婆", "姥姥", "老爷子", "老人家", "老公公", "老婆婆",
    ]

    static let commonNamePrefixes: Set<String> = ["阿", "小", "老", "大"]

    /// Characters that should NEVER appear at positions >= 2 in a real Chinese name.
    /// Pronouns, question words, particles, copula — absolutely reject.
    private static let strongRejectChars: Set<Character> = {
        Set("你我他她它这那哪什么怎么多么吧吗呢啊呀哦嗯哟啦嘛哈嘿喂咚罢了")
    }()

    /// Characters that are HIGHLY suspicious at positions 3-4 in a 3-4 char name.
    /// Grammar particles, directional verbs, common suffixes — reject if found at pos 3+.
    private static let weakRejectChars: Set<Character> = {
        Set("的着了过把被从以在于会就能能可不倒也还很都来来出去上回起开住好出进是到有能就在说")
    }()

    /// Grammar particles that are NEVER valid at position 3+ in a Chinese name.
    /// (的/了/着/过 are pure grammar markers; 来/可/好 can appear in real 3-char names)
    private static let grammarRejectChars: Set<Character> = {
        Set("的着了过")
    }()

    /// Characters at position 2+ that make a 2-char name almost certainly not a real name.
    /// Directional/positional suffixes, grammar particles, etc.
    private static let nonNameSuffix2Chars: Set<Character> = {
        Set("了着过的地得上下列里面前后边外内中旁左右东西南北")
    }()

    /// 3+‑char phrases that are known non‑name false positives (user-reported from 官仙).
    private static let nonNamePhrases: Set<String> = [
        "卫生间", "尤其是", "能感觉到", "有男朋友", "双腿发软", "安全通", "安全通道",
        "居高临下", "白的肌肤", "从后面", "有意思", "高跟鞋",
        "单膝跪地", "可以想象", "看在眼里", "能理解", "看起来", "听起来", "说起来",
        "看不起", "瞧不起", "来不及", "恨不得", "巴不得", "顾不得", "免不得",
        "不由得", "忍不住", "禁不住", "按不住", "挡不住", "拦不住", "瞒不住",
        "吃不住", "熬不住", "撑不住",
        "干什么", "凭什么", "为什么", "什么时候", "什么地方", "凭什么这么说",
        "一不小心", "一不留神", "一不留意", "一个不小心",
        "说到底", "说白了", "说穿了", "说来说去", "归根到底",
        "半信半疑", "将信将疑", "似信非信", "不可置信",
        "接下来", "然后呢", "所以说", "也就是说", "那就是说",
        "按道理", "按理说", "照理说", "照道理",
    ]

    /// 2‑char names that are common non‑name function‑word pairs.
    private static let nonNamePairs: Set<String> = [
        "所有", "这种", "那种", "每次", "只见", "忽见", "但见", "却见",
        "忽听", "只听", "但听", "却听", "突然", "忽然", "猛然", "顿时",
        "于是", "从此", "随后", "接着", "接着", "跟着", "然后", "转而",
        "关于", "对于", "由于", "因为", "为了", "除了", "经过", "通过",
        "我们", "你们", "他们", "她们", "它们", "自己", "大家", "诸位",
        "这个", "那个", "这里", "那里", "怎么", "什么", "这么", "那么",
        "没有", "不是", "就是", "还是", "但是", "可是", "然而", "而且",
        "如果", "因为", "所以", "虽然", "然后", "之后", "之前", "之中",
        "之中", "其中", "期间", "之间", "之际", "以来", "以前", "以后",
        "万一", "一切", "一个", "一种", "一次", "一时", "一刻",
        "难道", "究竟", "到底", "几乎", "似乎", "好像", "仿佛", "大约",
        "只见", "忽听", "便见", "就见",
        // 用户报告的2字假阳性
        "别人", "干部", "时间", "双手", "后排", "厉害", "卫生间",
        "单纯", "仰望", "何况", "别说", "包厢", "包裹", "帅气",
        "怀里", "成一", "成功", "成熟", "扶着", "房间",
        "明天", "明白", "明知", "有力", "有钱", "束缚",
        "沙发", "沙哑", "滑腻", "滑动", "满脸", "白色",
        "皮肤", "经验", "舒服", "解锁", "车子", "车门",
        "那一", "那你", "那头", "都好", "金主", "金钱",
        "马上", "麻烦", "头发", "水声", "哈哈", "白的",
        "肌肤", "江城", "能不", "有几", "高跟鞋", "安全通",
        "怀中", "那一", "地面", "摇头", "整个", "如今",
        "此处", "哪些", "那些", "全身", "眉头", "心头",
        "双手", "双手", "内心", "片刻", "刹那", "其中",
        "脚下", "边上", "头上", "脸上", "身上", "手里",
        "身后", "眼前", "面前",
    ]

    /// Check if a name looks like a real character name.
    static func looksLikeRealName(_ name: String) -> Bool {
        // Title suffix → always valid
        if name.count >= 2, titleSuffixes.contains(String(name.suffix(2))) { return true }

        // Known non-name phrases
        if nonNamePhrases.contains(name) { return false }

        let chars = Array(name)

        // 2-char: surname OR common prefix, AND not a known non-name pair
        if chars.count == 2 {
            guard firstCharIsSurname(name) || commonNamePrefixes.contains(String(name.prefix(1))) else { return false }
            if nonNamePairs.contains(name) { return false }
            // Reject if last char is directional/positional/particle
            if let last = name.last, nonNameSuffix2Chars.contains(String(last)) { return false }
            return true
        }

        // 3+ char: first char must be surname (or first 2 chars a compound surname)
        let hasSingleSurname = firstCharIsSurname(name)
        let hasCompoundSurname = chars.count >= 3 && compoundSurnames.contains(String(name.prefix(2)))
        guard hasSingleSurname || hasCompoundSurname else { return false }

        // Check positions 2+ for strong reject chars
        for i in 1..<chars.count {
            if strongRejectChars.contains(chars[i]) { return false }
        }

        // For 3-char names: check weak reject chars at position 3
        if chars.count == 3 {
            if grammarRejectChars.contains(chars[2]) { return false }
            if weakRejectChars.contains(chars[2]) { return false }
        }
        // For 4+ char names: check all weak reject chars at positions 3+
        if chars.count >= 4 {
            for i in 2..<chars.count {
                if weakRejectChars.contains(chars[i]) { return false }
            }
        }

        return true
    }

    // 百家姓单姓
    private static let singleSurnames: Set<String> = {
        let s = "赵钱孙李周吴郑王冯陈褚卫蒋沈韩杨朱秦尤许何吕施张孔曹严华金魏陶姜戚谢邹喻柏水窦章云苏潘葛奚范彭郎鲁韦昌马苗凤花方俞任袁柳酆鲍史唐费廉岑薛雷贺倪汤滕殷罗毕郝邬安常乐于时傅皮卞齐康伍余元卜顾孟平黄和穆萧尹姚邵舒汪祁毛禹狄米贝明臧计伏成戴谈宋茅庞熊纪屈项祝董杜阮蓝闵席季麻强贾路娄危江童颜郭梅盛林刁钟徐邱骆高夏蔡田樊胡凌霍虞万支柯咎管卢莫经房裘缪干解应宗宣丁贲邓郁单杭洪包诸左石崔吉钮龚程嵇邢滑裴陆荣翁荀羊於惠甄加封芮羿储靳汲邴糜松井段富巫乌焦巴弓牧隗山谷车侯宓蓬全郗班仰秋仲伊宫宁仇栾暴甘钭厉戎祖武符刘詹束龙叶幸司韶郜黎蓟薄印宿白怀蒲台从鄂索咸籍赖卓蔺屠蒙池乔阴胥能苍双闻莘党翟谭贡劳逄姬申扶堵冉宰郦雍璩桑桂濮牛寿通边扈燕冀郏浦尚农温别庄晏柴瞿阎充慕连茹习宦艾鱼容向古易慎戈廖庚终暨居衡步都耿满弘匡国文寇广禄阙东殳沃利蔚越夔隆师巩厍聂晁勾敖融冷訾辛阚那简饶空曾毋沙乜养鞠须丰巢关蒯相查后红游竺权逯盖益桓公晋楚法汝鄢涂钦缑亢况有商牟佘佴伯赏墨哈谯笪年爱阳佟琴言福岳帅"
        return Set(s.map { String($0) })
    }()

    private static let compoundSurnames: Set<String> = [
        "第五", "梁丘", "左丘", "东门", "百里", "东郭", "南门", "呼延",
        "万俟", "南宫", "段干", "西门", "司马", "上官", "欧阳", "夏侯",
        "诸葛", "闻人", "东方", "赫连", "皇甫", "尉迟", "公羊", "澹台",
        "公冶", "宗政", "濮阳", "淳于", "仲孙", "太叔", "申屠", "公孙",
        "乐正", "轩辕", "令狐", "钟离", "闾丘", "长孙", "慕容", "鲜于",
        "宇文", "司徒", "司空", "亓官", "司寇", "子车", "颛孙", "端木",
        "巫马", "公西", "漆雕", "壤驷", "公良", "夹谷", "宰父", "微生", "羊舌",
        "纳兰", "贺兰", "完颜", "拓跋", "耶律"
    ]

    // Pre-compiled regex patterns (compiled once, cached forever)
    private static let speechVerbPattern = RegexCache.shared.get(
        "([\\p{Han}]{2,4})(?:说|道|笑道|喊道|问道|怒道|哭道|叹道|骂道|喝道|叫道|低声道|轻声道|柔声道|冷声道|颤声道|沉声道|厉声道|正色道|正色说|接话道|插嘴道|接口道|应声道|抢先道|解释道|回答|追问|吩咐|叮嘱|嘱咐|呵斥|训斥|呵道)"
    )!
    private static let titlePattern = RegexCache.shared.get(
        "([\\p{Han}]{2,4})(?=先生|小姐|姑娘|公子|师父|师傅|少爷|太太|夫人|阁下|大人|兄台|贤弟|师妹|师姐|师兄|师弟|掌门|教主|帮主|盟主|庄主|岛主|前辈|婆婆|姥姥|老爷子|老人家)"
    )!
    private static let dialogueBeforeQuotePattern = RegexCache.shared.get(
        "([\\p{Han}]{2,4})[：:\\s]*[「\\u300c\\u201c『\\u300e]"
    )!
    // Name followed by comma + dialogue — "无忌，你怎么来了"
    private static let commaAddressPattern = RegexCache.shared.get(
        "([\\p{Han}]{2,4})[，,](?:[「\\u300c\\u201c『\\u300e])?"
    )!
    // Name + speech verb + punctuation/quote: 无忌说道："...
    private static let speechVerbQuotePattern = RegexCache.shared.get(
        "([\\p{Han}]{2,4})(?:说|道|笑道|喊道|问道|怒道)[：:]*[「\\u300c\\u201c『\\u300e\"'\\u2018\\u201c]"
    )!
    // Novel action + speech cross pattern: "纳兰嫣然！纳兰桀怒喝道"
    // Captures both the addressee and the speaker
    private static let exclamationSpeechPattern = RegexCache.shared.get(
        "([\\p{Han}]{2,4})[！!][「\\u300c\"'\\u201c]?([\\p{Han}]{2,4})(?:怒道|喝道|冷笑道|沉声道|厉声道|喊道|叫道)"
    )!
    // Name + novel action (no speech verb needed): "林动身形一闪"
    private static let novelActionPattern = RegexCache.shared.get(
        "([\\p{Han}]{2,4})(?:身形一闪|脸色一变|心中一动|心头一震|眉头一皱|脚步一顿|目光一凝|袖袍一挥|嘴角一勾|嘴角一撇|瞳孔一缩|身形一顿|面色一沉|脸色一沉|眼神一冷|神情一滞)"
    )!
    // Dialogue quote patterns
    private static let quoteExtractPatterns: [NSRegularExpression] = [
        RegexCache.shared.get("[「\\u300c]([^」\\u300d]+)[」\\u300d]")!,
        RegexCache.shared.get("['\\u2018]([^'\\u2019]+)['\\u2019]")!,
        RegexCache.shared.get("[\"\\u201c]([^\"\\u201d]+)[\"\\u201d]")!,
        RegexCache.shared.get("[『\\u300e]([^』\\u300f]+)[』\\u300f]")!,
    ]

    static func firstCharIsSurname(_ token: String) -> Bool {
        guard let first = token.first else { return false }
        return singleSurnames.contains(String(first))
    }

    private static func startsWithCompoundSurname(_ token: String) -> Bool {
        token.count >= 2 && compoundSurnames.contains(String(token.prefix(2)))
    }

    // MARK: - Alias resolution

    static func resolveAliases(_ names: [String]) -> [(canonical: String, aliases: [String])] {
        let nameSet = Set(names)
        var canonicalMap: [String: Set<String>] = [:]
        var isAlias: Set<String> = []

        let titleSuffixes = ["公子", "先生", "小姐", "姑娘", "掌门", "教主", "帮主", "庄主",
                             "岛主", "盟主", "前辈", "师父", "师傅", "师兄", "师弟", "师姐",
                             "师妹", "少爷", "大人", "将军", "王爷", "夫人", "太太"]

        for full in names where full.count == 3 {
            let suffix = String(full.suffix(2))
            if nameSet.contains(suffix) && suffix != full {
                canonicalMap[full, default: []].insert(suffix)
                isAlias.insert(suffix)
            }
        }

        for full in names where full.count == 4 {
            let suffix3 = String(full.suffix(3))
            if nameSet.contains(suffix3) && suffix3 != full {
                canonicalMap[full, default: []].insert(suffix3)
                isAlias.insert(suffix3)
            }
            let suffix2 = String(full.suffix(2))
            if nameSet.contains(suffix2) && suffix2 != full {
                canonicalMap[full, default: []].insert(suffix2)
                isAlias.insert(suffix2)
            }
        }

        for alias in names where alias.count == 3 {
            let firstChar = String(alias.prefix(1))
            let lastTwo = String(alias.suffix(2))
            guard titleSuffixes.contains(lastTwo) else { continue }
            guard singleSurnames.contains(firstChar) else { continue }
            for full in names where full.count >= 2 && full != alias {
                if String(full.prefix(1)) == firstChar && !isAlias.contains(full) {
                    canonicalMap[full, default: []].insert(alias)
                    isAlias.insert(alias)
                    break
                }
            }
        }

        for name in names where name.count == 2 && !isAlias.contains(name) {
            if !firstCharIsSurname(name) {
                canonicalMap[name] = []
            }
        }

        var result: [(String, [String])] = []
        var seenCanonical: Set<String> = []
        for name in names {
            if isAlias.contains(name) { continue }
            let aliases = canonicalMap[name]?.filter { $0 != name }.sorted() ?? []
            if !seenCanonical.contains(name) {
                result.append((name, aliases))
                seenCanonical.insert(name)
            }
        }
        return result
    }

    // MARK: - Phase 1: Dialogue regex on a chunk

    func extractDialogueNames(from chunk: String) -> [String] {
        let nsRange = NSRange(chunk.startIndex..<chunk.endIndex, in: chunk)
        var found = Set<String>()
        var colonNames = Set<String>()
        var commaNames = Set<String>()

        let patterns: [(NSRegularExpression, Int)] = [
            (Self.speechVerbPattern, 15),
            (Self.titlePattern, 12),
            (Self.dialogueBeforeQuotePattern, 12),
            (Self.commaAddressPattern, 10),
            (Self.speechVerbQuotePattern, 15),
            (Self.novelActionPattern, 12),
            (Self.exclamationSpeechPattern, 14),
        ]
        for (i, (pattern, _)) in patterns.enumerated() {
            pattern.enumerateMatches(in: chunk, range: nsRange) { match, _, _ in
                guard let m = match else { return }
                // Handle both single-capture and double-capture patterns
                let ranges: [Range<String.Index>] = (1..<m.numberOfRanges).compactMap { ri in
                    Range(m.range(at: ri), in: chunk)
                }
                for r in ranges {
                    let name = String(chunk[r])
                    if name.count >= 2 && name.count <= 4 && name.unicodeScalars.allSatisfy({ CharacterSet.ideographicCharacters.contains($0) }) && !isStopWord(name) {
                        found.insert(name)
                        if i == 2 { colonNames.insert(name) }
                        if i == 3 { commaNames.insert(name) }
                    }
                }
            }
        }

        let verbEndings: Set<String> = ["道", "嘴", "句", "口"]
        return found.filter { name in
            if colonNames.contains(name) {
                if verbEndings.contains(String(name.suffix(1))) { return false }
                if name.count >= 3 && !Self.firstCharIsSurname(name) && !Self.startsWithCompoundSurname(name) { return false }
            }
            if commaNames.contains(name) {
                if name.count >= 3 && !Self.firstCharIsSurname(name) && !Self.startsWithCompoundSurname(name) { return false }
            }
            // Accept: 3+ chars, or surname-based 2-char, or common prefixes (阿/小/老/大)
            return name.count >= 3 || Self.firstCharIsSurname(name) || Self.commonNamePrefixes.contains(String(name.prefix(1)))
        }
    }

    // MARK: - Phase 2: AC automaton

    func countWithAC(text: String, candidates: [String: Int]) -> [String: Int] {
        let ac = ACAutomaton()
        for name in candidates.keys where !isStopWord(name) && name.count >= 2 {
            ac.insert(name)
            // Also insert common substrings for better aliasing
            if name.count == 3 {
                let lastTwo = String(name.suffix(2))
                if Self.firstCharIsSurname(lastTwo) && !isStopWord(lastTwo) { ac.insert(lastTwo) }
            }
        }

        var scores = candidates
        let counts = ac.search(text)
        for (name, total) in counts {
            if name.count >= 2 && !isStopWord(name) {
                scores[name, default: 0] += total * 2
            }
        }
        return scores
    }

    // MARK: - Phase 2c: NL tagger validation

    /// Validate candidates using Apple's NL tagger.
    /// For each candidate, check up to 3 context windows.
    /// A candidate is valid if the NL tagger tags it as `.personalName` in at least 1 window.
    /// This eliminates common-word false positives (任务/别人/包裹 etc.)
    func validateWithNL(text: String, candidates: Set<String>) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.nameType])
        var validated = Set<String>()
        let contextRadius = 80

        for name in candidates {
            var found = false
            var searchStart = text.startIndex

            for _ in 0..<3 {
                guard let range = text.range(of: name, range: searchStart..<text.endIndex) else { break }
                let ws = text.index(range.lowerBound, offsetBy: -contextRadius, limitedBy: text.startIndex) ?? text.startIndex
                let we = text.index(range.upperBound, offsetBy: contextRadius, limitedBy: text.endIndex) ?? text.endIndex
                let window = String(text[ws..<we])

                tagger.string = window
                tagger.enumerateTags(in: window.startIndex..<window.endIndex, unit: .word, scheme: .nameType, options: [.joinNames, .omitWhitespace, .omitOther]) { tag, tagRange in
                    if tag == .personalName {
                        let taggedName = String(window[tagRange])
                        if taggedName == name {
                            found = true
                            return false
                        }
                    }
                    return true
                }

                if found { break }
                searchStart = range.upperBound
            }

            if found { validated.insert(name) }
        }

        return validated
    }

    // MARK: - Phase 3: NL NER on dialogue paragraphs (limited to first 500 dialogue paragraphs)

    func extractNLMissing(text: String, known: [String: Int]) -> [String: Int] {
        let knownNames = Set(known.keys)
        let tagger = NLTagger(tagSchemes: [.nameType])
        var result = [String: Int]()
        var dialogueCount = 0

        for para in text.components(separatedBy: "\n") where para.count >= 10 && para.count < 5000 {
            guard dialogueCount < 500 else { break }
            if !para.contains("说") && !para.contains("道") && !para.contains("喊") &&
               !para.contains("问") && !para.contains("「") { continue }
            dialogueCount += 1
            tagger.string = para
            tagger.enumerateTags(in: para.startIndex..<para.endIndex, unit: .word, scheme: .nameType, options: [.joinNames, .omitWhitespace, .omitOther]) { tag, range in
                if tag == .personalName {
                    let name = String(para[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if name.count >= 2 && name.count <= 4 && !knownNames.contains(name) && !isStopWord(name) {
                        if name.count == 2 && !Self.firstCharIsSurname(name) { return true }
                        result[name, default: 0] += 1
                    }
                }
                return true
            }
        }
        return result
    }

    // MARK: - Dialogue detection

    func detectDialogues(in text: String) -> [DialogueMatch] {
        var results: [DialogueMatch] = []
        var lastKnownSpeaker: String?
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)

        for pattern in Self.quoteExtractPatterns {
            pattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
                guard let m = match, m.numberOfRanges > 1 else { return }
                guard let range1 = Range(m.range(at: 1), in: text) else { return }
                let content = String(text[range1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return }

                // Infer speaker from preceding context (up to 200 chars)
                let lower = m.range(at: 1).lowerBound
                let beforeEnd = text.index(text.startIndex, offsetBy: lower)
                let beforeStart = text.index(beforeEnd, offsetBy: -min(200, lower), limitedBy: text.startIndex) ?? text.startIndex
                let context = String(text[beforeStart..<beforeEnd])

                if let speaker = inferSpeakerFromContext(context) {
                    lastKnownSpeaker = speaker
                }

                results.append(DialogueMatch(speaker: lastKnownSpeaker, content: content, range: range1))
            }
        }

        return results
    }

    private func inferSpeakerFromContext(_ precedingText: String) -> String? {
        // Must be at end of text (immediately before quote)
        let trimmed = precedingText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Priority 1: "Name" immediately followed by speech verb + colon
        let speechVerbPattern = RegexCache.shared.get(
            "([\\p{Han}]{2,4})(?:说|道|笑道|喊道|问道|怒道|哭道|叹道|骂道|喝道|叫道|低声道|轻声道|柔声道|冷声道|颤声道|沉声道|厉声道|正色道|接话道|插嘴道|接口道|应声道|抢先道|解释道|回答|追问|吩咐|叮嘱|嘱咐|呵斥|训斥)[：:]?$"
        )!
        let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        if let match = speechVerbPattern.matches(in: trimmed, range: nsRange).last {
            let raw = String(trimmed[Range(match.range(at: 1), in: trimmed)!])
            if raw.count >= 2 && raw.count <= 4 { return raw }
        }

        // Priority 2: "Name：" or "Name:" right before quote
        let colonPattern = RegexCache.shared.get("([\\p{Han}]{2,4})[：:][\\s]*$")!
        if let match = colonPattern.matches(in: trimmed, range: nsRange).last {
            let raw = String(trimmed[Range(match.range(at: 1), in: trimmed)!])
            if raw.count >= 2 && raw.count <= 4 { return raw }
        }

        // Priority 3: Title suffix pattern
        let titlePattern = RegexCache.shared.get("([\\p{Han}]{2,4})(?:先生|小姐|姑娘|公子|师父|师傅|少爷|太太|夫人|阁下|大人|前辈|掌门|教主)[：:]?$")!
        if let match = titlePattern.matches(in: trimmed, range: nsRange).last {
            let raw = String(trimmed[Range(match.range(at: 1), in: trimmed)!])
            if raw.count >= 2 && raw.count <= 4 { return raw }
        }

        return nil
    }

    // MARK: - Speaker inference (for script building)

    func inferSpeaker(from line: String, knownCharacters: [String]) -> String? {
        // Priority 1: "Name：" or "Name:" at start
        if let groups = line.firstMatch(regex: "^([\\p{Han}]{2,4})[：:]"), groups.count > 1 {
            return groups[1]
        }
        // Priority 2: speech verb prefix
        if let groups = line.firstMatch(regex: "([\\p{Han}]{2,4})(?=笑道|说道|问道|喊道|叫道|喝道|骂道|答道|回答|解释说|解释道|忽然道|低声道|轻声道|怒道|叹道|哭道|骂道|喝道|厉声道|正色道)"), groups.count > 1 {
            return groups[1]
        }
        // Priority 3: "Name：" before quote
        if let groups = line.firstMatch(regex: "([\\p{Han}]{2,4})[：:][「『“‘]"), groups.count > 1 {
            return groups[1]
        }
        // Priority 4: Known character name appearing at line start
        for name in knownCharacters {
            if line.hasPrefix(name) {
                return name
            }
        }
        // Priority 5: Known character name + comma (addressed to someone)
        for name in knownCharacters {
            if line.hasPrefix("\(name)，") || line.hasPrefix("\(name),") {
                return name
            }
        }
        return nil
    }

    // MARK: - Relationship graph

    func buildRelationshipGraph(text: String, characterNames: [String]) -> [RelationshipEdge] {
        let nameSet = Set(characterNames)
        var cooccurrence: [String: [String: Int]] = [:]
        let paragraphs = text.components(separatedBy: "\n")

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
        let angryWords = ["怒", "愤", "恨", "吼", "骂", "怒道", "喝道", "呵斥", "训斥", "怒喝"]
        let sadWords = ["叹", "悲", "哭", "哀", "泣", "叹道", "哭道", "轻声", "低声", "哽咽", "啜泣", "悲伤", "凄凉"]
        let cheerfulWords = ["笑", "喜", "欢", "乐", "开心", "笑道", "莞尔", "玩笑", "高兴"]

        let hasExclamation = line.contains("！")
        let hasQuestion = line.contains("？") || line.contains("?")

        if hasExclamation {
            for w in angryWords where line.contains(w) {
                return ToneResult(style: "angry", pitchAdjust: 12, rateAdjust: 10)
            }
            for w in cheerfulWords where line.contains(w) {
                return ToneResult(style: "cheerful", pitchAdjust: 8, rateAdjust: 5)
            }
            if hasQuestion {
                return ToneResult(style: "angry", pitchAdjust: 10, rateAdjust: 8)
            }
            return ToneResult(style: "neutral", pitchAdjust: 5, rateAdjust: 3)
        }
        if hasQuestion {
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

    func isStopWord(_ word: String) -> Bool {
        let stops: Set<String> = [
            "第一", "第二", "第三", "第四", "第五", "第十", "最后", "开始", "结束",
            "不过", "突然", "然后", "但是", "因为", "所以", "虽然", "如果",
            "可是", "只是", "就是", "还是", "这个", "那个", "什么", "怎么",
            "这样", "那样", "这些", "那些", "这里", "那里", "时候", "以后",
            "之前", "没有", "不是", "自己", "他们", "她们", "你们", "我们",
            "大家", "一切", "一个", "一种", "别的", "各自", "对面", "眼前",
            "面前", "身后", "背后", "手中", "脚下", "天上", "地下", "心中",
            "脸上", "眼里", "嘴里", "身上", "头上", "晚上", "上午", "下午",
            "方才", "刚才", "此刻", "现在", "原来", "本来", "起来", "出来",
            "过来", "回来", "进去", "出去", "看见", "看到", "听见", "听到",
            "知道", "觉得", "感觉", "有点", "有些", "十分", "非常", "特别",
            "更加", "稍微", "轻轻", "慢慢", "渐渐", "终于", "从未", "已然",
            "尚未", "已经", "曾经", "而且", "并且", "或者", "不但", "不仅",
            "甚至", "连同", "以及", "全都", "全部", "凡是", "各位", "诸位",
            "自从", "由于", "关于", "对于", "根据", "先生", "小姐", "姑娘",
            "公子", "师父", "师傅", "少爷", "夫人", "阁下", "大人", "前辈",
            "掌门", "教主", "帮主",
            // 常被误认为人名的2字普通词语 (用户反馈报告)
            "别人", "干部", "时间", "双手", "后排", "厉害", "单纯",
            "仰望", "何况", "别说", "包厢", "包裹", "帅气",
            "怀里", "成一", "成功", "成熟", "扶着", "房间",
            "明天", "明白", "明知", "有力", "有钱", "束缚",
            "沙发", "沙哑", "滑腻", "滑动", "满脸", "白色",
            "皮肤", "经验", "舒服", "解锁", "车子", "车门",
            "那一", "那你", "那头", "都好", "金主", "金钱",
            "马上", "麻烦", "头发",
            "有一", "有的", "温柔", "应该", "那就", "怀中", "解释", "空气",
            "方式", "闻言", "温热", "简直", "何人", "许久", "强者", "路上",
            "干净", "那边", "那位", "一脸", "不由", "不错", "不愿", "不到",
            "不敢", "不能", "不会", "不好", "不用", "不知", "不断", "不停",
            "轻声", "师尊", "宗主", "师兄", "师姐", "师妹", "师弟", "怀中",
            "于是", "那啥", "那个", "算了", "还能", "还是", "再说", "回头",
            "哪天", "到时", "按理", "要不", "或是", "除了", "其中", "其他",
            "其余", "哪些", "哪些", "接着", "跟着", "反正", "总之", "虽说",
            "虽说", "若非", "待到", "直到", "趁着", "凭着", "靠着", "顺着",
            "照着", "朝着", "沿着", "经过", "通过", "周围", "附近", "旁边",
            "大约", "至少", "最多", "最少", "多半", "还是", "必然", "自然",
            "果然", "居然", "竟然", "难道", "究竟", "到底", "毕竟", "反正",
            "当然", "总归", "或是", "或是", "还有", "尚有", "唯有", "唯有",
            "只有", "惟有", "另外", "此外", "同时", "前后", "左右", "前后",
            "许多",
            // 常见非人名高频词 (补充)
            "万一", "不知", "之间", "之前", "之后", "之时", "之际", "之类",
            "之中", "之一", "其中", "其它", "其余", "别的", "各自", "彼此",
            "互相", "相对", "绝对", "完全", "全部", "全都", "整个", "全体",
            "每次", "每天", "每年", "每月", "每周", "多年", "连日", "连夜",
            "不断", "不停", "不止", "不仅", "不只", "不禁", "不由", "不由",
            "连忙", "急忙", "赶紧", "赶快", "迅速", "快速", "飞快", "急速",
            "始终", "一直", "一向", "一贯", "从来", "历来", "向来", "本来",
            "原来", "如此", "这样", "那样", "这么", "那么", "怎么", "多么",
            "各自", "分别", "依次", "逐一", "逐个", "一一", "全都", "皆",
            "忽然", "猛然", "骤然", "蓦然", "陡然", "霍然", "恍然", "愕然",
            "竟然", "居然", "果然", "当然", "必然", "自然", "显然", "仍然",
            "依旧", "依然", "仍然", "仍旧", "还是", "仍是", "仍是", "仍是",
            "只是", "但是", "可是", "却是", "而是", "倒是", "却是", "正是",
            "就是", "总是", "算是", "算是", "凡是", "凡是", "凡是",
            "丁香小舌", "樱桃小嘴", "纤纤玉手", "满头大汗", "泪流满面",
            "一个女孩", "一个男子", "一个声音", "一个女人", "一个男人",
            "一个少年", "一个青年", "一个老人", "一个小孩", "一个孩子",
            "一个姑娘", "一个小伙", "一个丫鬟", "一个仆人", "一个侍卫",
            "那个声音", "那个女子", "那个男人", "那个人", "那个女孩",
            "那个少年", "那个丫鬟", "那个侍卫", "那个家伙", "那个东西",
            "这个声音", "这个女子", "这个男孩", "这个女孩", "这个少年",
            "这个丫鬟", "这个侍卫", "这个家伙", "这个孩子", "两个孩子",
            "三个孩子", "几个人", "两个人", "三个人", "几个人", "所有人",
            "众人", "两人", "三人", "多人", "数人", "各人", "诸人",
            "只见", "却见", "但见", "忽见", "忽听", "只听", "但听",
            // 常见3-4字非人名误识
            "卫生间", "尤其是", "能感觉到", "有男朋友", "双腿发软", "安全通",
            "一切都", "不客气", "不好意思", "没关系", "没办法", "无所谓", "不知道",
            "为什么", "什么事", "怎么回事", "怎么说", "这么说", "那么说",
            "比如说", "就是说", "那就是", "那就是",
            "是不是", "要不要", "能不能", "会不会", "敢不敢", "有没有", "行不行", "好不好",
            "了不起", "了不得", "不得了", "不得已", "不要紧",
            "转过头", "转过身", "回过头", "抬起头", "低下头", "睁开眼", "闭上眼",
            "睁开眼", "看了看", "听了听", "想了想", "笑了笑", "笑了笑",
            "点了点头", "摇了摇头", "摆摆手", "挥挥手",
            "一句话", "一番话", "一番话", "一席话",
            "说起来", "说起来", "说起来", "说起来", "说起来",
            "说实话", "老实说", "准确说", "确切说", "认真说",
            "可以说", "可以说", "可以说", "可以说是",
            "应该说", "应该说", "应该说", "应该说是",
            "意味着", "意味着", "意味着",
            "来着", "算来", "想来", "看来", "听来",
            "看样子", "看起来", "听起来", "说起来", "说起来",
            "只见那", "却见那", "但见那", "忽见那",
            "那个谁", "那个谁", "那个人", "那个家伙",
            "这一来", "这一下", "这一下", "这一来",
            "不得不", "不得", "不可", "不能", "不会", "不敢",
            "还要", "还有", "只能", "只能", "只有", "只能",
            "只见那", "忽然间", "突然间", "猛然间", "骤然间",
            "片刻间", "一瞬间", "一刹那", "眨眼间",
            "谁知道", "谁知道", "谁知道",
            "没想到", "想不到", "料不到", "猜不到",
            "忍不住", "禁不住", "按不住",
            "不由说", "不用说", "不用说", "不用说道", "不用问",
            "肯定说", "肯定说", "断定说", "断定",
            "回头说", "回头说", "回头道",
            "却说", "却说", "且说", "话说", "单说",
            "再说", "再说", "再说", "再说",
            "只见那个", "只见一个", "只见一位",
            "却见一个", "便见一个", "就见一个",
            "只听一个", "只听一人", "只听有人",
            "突然一个", "忽然一个", "突然一位",
             "只见那", "忽听那", "只听那",
             // 用户报告的3+字假阳性
             "安全通道", "居高临下", "白的肌肤", "从后面", "有意思", "高跟鞋",
        ]
        return stops.contains(word) ||
               word.hasPrefix("第") ||
               word.hasSuffix("章") || word.hasSuffix("回") || word.hasSuffix("节")
    }
}

// MARK: - CharacterSet Extension

extension CharacterSet {
    static let ideographicCharacters: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: UnicodeScalar(UInt32(0x4E00))!..<UnicodeScalar(UInt32(0xA000))!)
        set.insert(charactersIn: UnicodeScalar(UInt32(0x3400))!..<UnicodeScalar(UInt32(0x4DC0))!)
        set.insert(charactersIn: UnicodeScalar(UInt32(0xF900))!..<UnicodeScalar(UInt32(0xFB00))!)
        return set
    }()
}

// MARK: - String Extension (regex helpers)

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