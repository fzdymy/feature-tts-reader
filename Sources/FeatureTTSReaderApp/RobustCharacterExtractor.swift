@preconcurrency import Foundation
@preconcurrency import NaturalLanguage

// MARK: - Data Types

public struct ExtractedCharacter: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public var gender: String = "未知"
    public var age: String = "未知"
    public var tone: String = "平稳"
    public var style: String = "neutral"
    public var rate: Int = 0
    public var pitch: Int = 0
    public var confidence: Double = 0.5
    public var isNarrator: Bool = false
    public var aliases: [String] = []
    public var voiceID: String = ""
    public var sampleLines: [String] = []

    public init(name: String) {
        self.name = name
    }
}

public struct ExtractionResult {
    public let characters: [ExtractedCharacter]
    public let narratorName: String?
    public let totalDialogues: Int
    public let textLength: Int
    public let extractionMethod: String
}

// MARK: - Chinese Name Patterns

private enum ChineseNamePatterns {
    static let singleSurnames: Set<String> = {
        let s = "赵钱孙李周吴郑王冯陈褚卫蒋沈韩杨朱秦尤许何吕施张孔曹严华金魏陶姜戚谢邹喻柏水窦章云苏潘葛奚范彭郎鲁韦昌马苗凤花方俞任袁柳酆鲍史唐费廉岑薛雷贺倪汤滕殷罗毕郝邬安常乐于时傅皮卞齐康伍余元卜顾孟平黄和穆萧尹姚邵舒汪祁毛禹狄米贝明臧计伏成戴谈宋茅庞熊纪屈项祝董杜阮蓝闵席季麻强贾路娄危江童颜郭梅盛林刁钟徐邱骆高夏蔡田樊胡凌霍虞万支柯咎管卢莫经房裘缪干解应宗宣丁贲邓郁单杭洪包诸左石崔吉钮龚程嵇邢滑裴陆荣翁荀羊於惠甄加封芮羿储靳汲邴糜松井段富巫乌焦巴弓牧隗山谷车侯宓蓬全郗班仰秋仲伊宫宁仇栾暴甘钭厉戎祖武符刘詹束龙叶幸司韶郜黎蓟薄印宿白怀蒲台从鄂索咸籍赖卓蔺屠蒙池乔阴胥能苍双闻莘党翟谭贡劳逄姬申扶堵冉宰郦雍璩桑桂濮牛寿通边扈燕冀郏浦尚农温别庄晏柴瞿阎充慕连茹习宦艾鱼容向古易慎戈廖庚终暨居衡步都耿满弘匡国文寇广禄阙东殳沃利蔚越夔隆师巩厍聂晁勾敖融冷訾辛阚那简饶空曾毋沙乜养鞠须丰巢关蒯相查后红游竺权逯盖益桓公晋楚法汝鄢涂钦缑亢况有商牟佘佴伯赏墨哈谯笪年爱阳佟琴言福岳帅"
        return Set(s.map { String($0) })
    }()

    static let compoundSurnames: Set<String> = [
        "第五", "梁丘", "左丘", "东门", "百里", "东郭", "南门", "呼延",
        "万俟", "南宫", "段干", "西门", "司马", "上官", "欧阳", "夏侯",
        "诸葛", "闻人", "东方", "赫连", "皇甫", "尉迟", "公羊", "澹台",
        "公冶", "宗政", "濮阳", "淳于", "仲孙", "太叔", "申屠", "公孙",
        "乐正", "轩辕", "令狐", "钟离", "闾丘", "长孙", "慕容", "鲜于",
        "宇文", "司徒", "司空", "亓官", "司寇", "子车", "颛孙", "端木",
        "巫马", "公西", "漆雕", "壤驷", "公良", "夹谷", "宰父", "微生", "羊舌",
        "纳兰", "贺兰", "完颜", "拓跋", "耶律"
    ]

    static let titleSuffixes: Set<String> = [
        "先生", "小姐", "姑娘", "公子", "师父", "师傅", "少爷", "太太",
        "夫人", "阁下", "大人", "前辈", "掌门", "教主", "帮主", "盟主",
        "庄主", "岛主", "兄台", "贤弟", "师妹", "师姐", "师兄", "师弟",
        "婆婆", "姥姥", "老爷子", "老人家", "老公公", "老婆婆",
        "哥哥", "姐姐", "弟弟", "妹妹", "叔叔", "婶婶", "伯伯", "舅舅",
        "舅妈", "姑姑", "姑父", "姨妈", "姨父", "长辈", "晚辈", "同门",
        "师兄", "师姐", "师弟", "师妹", "师叔", "师伯", "师父", "师傅",
        "师尊", "宗主", "长老", "护法", "堂主", "副堂主",
    ]

    static let namePrefixes: Set<String> = ["阿", "小", "老", "大", "初"]

    static let nonNameSuffix2Chars: Set<Character> = {
        Set("了着过的地得上下列里面前后边外内中旁左右东西南北年月日时分秒")
    }()

    static let strongRejectChars: Set<Character> = {
        Set("你我他她它这那哪什么怎么多么吧吗呢啊呀哦嗯哟啦嘛哈嘿喂咚罢了")
    }()

    static let weakRejectChars: Set<Character> = {
        Set("的着了过把被从以在于会就能能可不倒也还很都来来出去上回起开住好出进是到有能就在说")
    }()

    static let grammarRejectChars: Set<Character> = {
        Set("的着了过")
    }()

    static let nonNamePhrases: Set<String> = [
        "卫生间", "尤其是", "能感觉到", "有男朋友", "双腿发软", "安全通", "安全通道",
        "居高临下", "白的肌肤", "从后面", "有意思", "高跟鞋",
        "单膝跪地", "可以想象", "看在眼里", "能理解", "看起来", "听起来", "说起来",
        "看不起", "瞧不起", "来不及", "恨不得", "巴不得", "顾不得", "免不得",
        "不由得", "忍不住", "禁不住", "按不住", "挡不住", "拦不住", "瞒不住",
        "吃不住", "熬不住", "撑不住",
        "干什么", "凭什么", "为什么", "什么时候", "什么地方", "凭什么这么说",
        "一不小心", "一不留神", "一不留意", "一个不小心",
        "说到底", "说白了", "说穿了", "说来说去", "归根到底",
        "接下来", "然后呢", "所以说", "也就是说", "那就是说",
        "按道理", "按理说", "照理说", "照道理",
        "半信半疑", "将信将疑", "似信非信", "不可置信",
        "究竟", "到底", "几乎", "似乎", "好像", "仿佛", "大约",
    ]

    static let nonNamePairs: Set<String> = [
        "所有", "这种", "那种", "每次", "只见", "忽见", "但见", "却见",
        "忽听", "只听", "但听", "却听", "突然", "忽然", "猛然", "顿时",
        "于是", "从此", "随后", "接着", "跟着", "然后", "转而",
        "关于", "对于", "由于", "因为", "为了", "除了", "经过", "通过",
        "我们", "你们", "他们", "她们", "它们", "自己", "大家", "诸位",
        "这个", "那个", "这里", "那里", "怎么", "什么", "这么", "那些",
        "没有", "不是", "就是", "还是", "但是", "可是", "然而", "而且",
        "如果", "因为", "所以", "虽然", "然后", "之后", "之前", "之中",
        "之中", "那些", "这些", "每次", "每天", "万一", "一切", "一个",
        "一种", "一次", "一时", "一刻", "难道", "究竟", "到底", "几乎",
        "似乎", "好像", "仿佛", "大约", "只见", "忽听", "便见", "就见",
        "别人", "干部", "时间", "双手", "后排", "厉害", "单纯",
        "仰望", "何况", "别说", "包厢", "包裹", "帅气",
        "怀里", "成一", "成功", "成熟", "扶着", "房间",
        "明天", "明白", "明知", "有力", "有钱", "束缚",
        "沙发", "沙哑", "滑腻", "滑动", "满脸", "白色",
        "皮肤", "经验", "舒服", "解锁", "车子", "车门",
        "那一", "那你", "那头", "都好", "金主", "金钱",
        "马上", "麻烦", "头发", "水声", "哈哈", "白的",
        "肌肤", "江城", "能不", "有几", "高跟鞋", "安全通",
        "怀中", "那一", "地面", "摇头", "整个", "如今",
        "此处", "哪些", "那些", "全身", "眉头", "心头",
        "双手", "内心", "片刻", "刹那", "那些",
        "脚下", "边上", "头上", "脸上", "身上", "手里",
        "身后", "眼前", "面前", "那些", "这些", "这里", "那里",
    ]

    static let stopWords: Set<String> = [
        "第一", "第二", "第三", "第四", "第五", "第十", "最后", "开始", "结束",
        "不过", "突然", "然后", "但是", "因为", "所以", "虽然", "如果",
        "可是", "只是", "就是", "还是", "这个", "那个", "什么", "怎么",
        "这样", "那些", "这些", "这里", "那里", "时候", "以后",
        "之前", "没有", "不是", "自己", "他们", "她们", "你们", "我们",
        "大家", "一切", "一个", "一种", "别的", "各自", "对面", "眼前",
        "面前", "身后", "背后", "手中", "脚下", "天上", "地下", "心中",
        "脸上", "眼里", "嘴里", "身上", "头上", "晚上", "上午", "下午",
        "方才", "刚才", "此刻", "现在", "原来", "本来", "起来", "出来",
        "过来", "回来", "进去", "出去", "看见", "看到", "听见", "听到",
        "知道", "觉得", "感觉", "有点", "有些", "十分", "非常", "特别",
        "更加", "稍微", "轻轻", "慢慢", "渐渐", "终于", "从未", "已然",
        "尚未", "已经", "曾经", "而且", "并且", "或者", "不但", "那些",
        "甚至", "连同", "以及", "全都", "全部", "凡是", "各位", "诸位",
        "自从", "由于", "关于", "对于", "根据", "那些", "那些", "每个", "那些",
        "万一", "不知", "之间", "之前", "之后", "之时", "之际", "之类",
        "之中", "之一", "那些", "那些", "其他", "各自", "彼此",
        "互相", "相对", "绝对", "完全", "全部", "全都", "整个", "全体",
        "每次", "每天", "每年", "每月", "每周", "多年", "连日", "连夜",
        "不断", "不停", "不止", "不仅", "不只", "不禁", "不由", "不由",
        "连忙", "急忙", "赶紧", "赶快", "迅速", "快速", "飞快", "急速",
        "始终", "一直", "一向", "一贯", "从来", "历来", "向来", "本来",
        "原来", "那些", "那些", "每个", "每次",
        "万一", "不知", "那些", "那些", "那些", "那些", "那些",
        "那些", "那些", "那些", "那些",
        "那些", "那些", "那些", "那些",
        "那些", "那些", "那些", "那些",
        "那些", "那些", "那些", "那些",
    ]

    static let speechVerbs: Set<String> = [
        "说", "道", "笑道", "喊道", "问道", "怒道", "哭道", "叹道",
        "骂道", "喝道", "叫道", "低声道", "轻声道", "柔声道", "冷声道",
        "颤声道", "沉声道", "厉声道", "正色道", "接话道", "插嘴道",
        "接口道", "应声道", "抢先道", "解释道", "回答", "追问",
        "吩咐", "叮嘱", "嘱咐", "呵斥", "训斥", "呵道", "喊道", "唤道",
        "低语", "细语", "私语", "耳语", "心道", "暗道", "忖道",
        "笑", "哭", "叹", "怒", "骂", "喝", "吼", "叫", "唤",
    ]

    static let actionVerbs: Set<String> = [
        "身形一闪", "脸色一变", "心中一动", "心头一震", "眉头一皱",
        "脚步一顿", "目光一凝", "袖袍一挥", "嘴角一勾", "嘴角一撇",
        "瞳孔一缩", "身形一顿", "面色一沉", "脸色一沉", "眼神一冷",
        "神情一滞", "脸色大变", "神色大变", "心中大惊", "心头大震",
    ]
}

// MARK: - Regex Patterns

private enum RegexPatterns {
    static let coreSpeaker = try? NSRegularExpression(
        pattern: "([\\p{Han}]{2,4})(?:说|道|笑道|喊道|问道|怒道|哭道|叹道|骂道|喝道|叫道|低声道|轻声道|柔声道|冷声道|颤声道|沉声道|厉声道|正色道|正色说|接话道|插嘴道|接口道|应声道|抢先道|解释道|回答|追问|吩咐|叮嘱|嘱咐|呵斥|训斥|呵道)[：:\\s]*[「\\u300c\\u201c『\\u300e\"'\\u2018\\u201c]?",
        options: [.dotMatchesLineSeparators]
    )

    static let colonBeforeQuote = try? NSRegularExpression(
        pattern: "([\\p{Han}]{2,4})[：:][\\s]*[「\\u300c\\u201c『\\u300e]",
        options: []
    )

    static let commaAddress = try? NSRegularExpression(
        pattern: "([\\p{Han}]{2,4})[，,]",
        options: []
    )

    static let titleSuffix = try? NSRegularExpression(
        pattern: "([\\p{Han}]{2,4})(?=先生|小姐|姑娘|公子|师父|师傅|少爷|太太|夫人|阁下|大人|前辈|掌门|教主|帮主|盟主|庄主|岛主|前辈|婆婆|姥姥|老爷子|老人家)",
        options: []
    )

    static let novelAction = try? NSRegularExpression(
        pattern: "([\\p{Han}]{2,4})(?:身形一闪|脸色一变|心中一动|心头一震|眉头一皱|脚步一顿|目光一凝|袖袍一挥|嘴角一勾|嘴角一撇|瞳孔一缩|身形一顿|面色一沉|脸色一沉|眼神一冷|神情一滞|脸色大变|神色大变|心中大惊|心头大震)",
        options: []
    )

    static let nameWithColon = try? NSRegularExpression(
        pattern: "([\\p{Han}]{2,4})[：:][\\s]*[「\\u300c\\u201c『\\u300e]",
        options: []
    )

    static let quoteExtract = [
        try? NSRegularExpression(pattern: "[「\\u300c]([^」\\u300d]+)[」\\u300d]", options: []),
        try? NSRegularExpression(pattern: "['\\u2018]([^'\\u2019]+)['\\u2019]", options: []),
        try? NSRegularExpression(pattern: "[\"\\u201c]([^\"\\u201d]+)[\"\\u201d]", options: []),
        try? NSRegularExpression(pattern: "[『\\u300e]([^』\\u300f]+)[』\\u300f]", options: []),
    ].compactMap { $0 }
}

// MARK: - Robust Character Extractor

public final class RobustCharacterExtractor {
    public struct Config: Sendable {
        public var maxCharacters: Int = 20
        public var minFrequency: Int = 2
        public var maxContextLength: Int = 500
        public var useNLTagger: Bool = true
        public var aggressiveMode: Bool = true
        public var includeTitles: Bool = true
        public var includeCommaAddress: Bool = true

        public static let `default` = Config()
        public static let aggressive = Config(
            maxCharacters: 20,
            minFrequency: 1,
            maxContextLength: 500,
            useNLTagger: true,
            aggressiveMode: true,
            includeTitles: true,
            includeCommaAddress: true
        )
    }

    private let config: Config
    private let nlTagger = NLTagger(tagSchemes: [.nameType])

    public init(config: Config = .default) {
        self.config = config
    }

    public func extract(from text: String) -> ExtractionResult {
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        let length = normalized.count

        let candidates = extractCandidates(from: normalized)
        let frequencies = countFrequencies(text: normalized, candidates: candidates)
        let characters = buildProfiles(from: frequencies, text: normalized, originalText: text)
        let narrator = identifyNarrator(from: characters, text: normalized)
        let finalCharacters = assignVoices(to: characters, narrator: narrator)

        return ExtractionResult(
            characters: finalCharacters,
            narratorName: narrator?.name,
            totalDialogues: extractDialogues(from: normalized).count,
            textLength: length,
            extractionMethod: "RobustCharacterExtractor v1.0"
        )
    }

    // MARK: - Phase 1: Candidate Extraction

    private func extractCandidates(from text: String) -> Set<String> {
        var candidates = Set<String>()
        let paragraphs = text.components(separatedBy: .newlines)

        for para in paragraphs {
            if hasDialogueFeatures(para) {
                candidates.formUnion(extractFromDialogueParagraph(para))
            }
        }

        candidates.formUnion(extractFromTitleSuffixes(text))
        candidates.formUnion(extractColonBeforeQuote(text))

        if config.aggressiveMode {
            candidates.formUnion(extractCommaAddress(text))
        }

        candidates.formUnion(extractNovelActions(text))

        if config.useNLTagger {
            candidates.formUnion(extractWithNLTagger(text))
        }

        return candidates.filter { isValidCandidate($0) }
    }

    private func hasDialogueFeatures(_ para: String) -> Bool {
        para.contains("“") || para.contains("「") || para.contains("」") ||
        para.contains("道") || para.contains("说") || para.contains("问") ||
        para.contains("喊") || para.contains("笑") || para.contains("笑道") ||
        para.contains("怒道") || para.contains("笑道") || para.contains("叫道")
    }

    private func extractFromDialogueParagraph(_ para: String) -> Set<String> {
        var found = Set<String>()
        let nsRange = NSRange(para.startIndex..<para.endIndex, in: para)

        let patterns: [NSRegularExpression?] = [RegexPatterns.coreSpeaker, RegexPatterns.novelAction, RegexPatterns.titleSuffix]
        for pattern in patterns.compactMap({ $0 }) {
            pattern.enumerateMatches(in: para, range: nsRange) { match, _, _ in
                guard let m = match, let r = Range(m.range(at: 1), in: para) else { return }
                let nameCandidate = String(para[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidName(nameCandidate) { found.insert(nameCandidate) }
            }
        }
        return found
    }

    private func extractFromTitleSuffixes(_ text: String) -> Set<String> {
        var found = Set<String>()
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        if let pattern = RegexPatterns.titleSuffix {
            pattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
                guard let m = match, let r = Range(m.range(at: 1), in: text) else { return }
                let name = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidName(name) { found.insert(name) }
            }
        }
        return found
    }

    private func extractColonBeforeQuote(_ text: String) -> Set<String> {
        var found = Set<String>()
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        if let pattern = RegexPatterns.colonBeforeQuote {
            pattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
                guard let m = match, let r = Range(m.range(at: 1), in: text) else { return }
                let name = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidName(name) { found.insert(name) }
            }
        }
        return found
    }

    private func extractCommaAddress(_ text: String) -> Set<String> {
        var found = Set<String>()
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        if let pattern = try? NSRegularExpression(pattern: "([\\p{Han}]{2,4})[，,][^，,]*[「\\u300c\\u201c]", options: []) {
            pattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
                guard let m = match, let r = Range(m.range(at: 1), in: text) else { return }
                let name = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidName(name) { found.insert(name) }
            }
        }
        return found
    }

    private func extractNovelActions(_ text: String) -> Set<String> {
        var found = Set<String>()
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        if let pattern = RegexPatterns.novelAction {
            pattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
                guard let m = match, let r = Range(m.range(at: 1), in: text) else { return }
                let name = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidName(name) { found.insert(name) }
            }
        }
        return found
    }

    private func extractWithNLTagger(_ text: String) -> Set<String> {
        var found = Set<String>()
        let paragraphs = text.components(separatedBy: .newlines)

        for para in paragraphs where para.count >= 10 && para.count < 5000 {
            if !hasDialogueFeatures(para) { continue }

            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = para
            tagger.enumerateTags(in: para.startIndex..<para.endIndex, unit: .word, scheme: .nameType, options: [.joinNames, .omitWhitespace, .omitOther]) { tag, range in
                if tag == .personalName {
                    let name = String(para[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if isValidName(name) {
                        found.insert(name)
                    }
                }
                return true
            }
        }
        return found
    }

    // MARK: - Helpers

    private func isValidCandidate(_ name: String) -> Bool {
        name.count >= 2 && name.count <= 4 &&
        !ChineseNamePatterns.stopWords.contains(name) &&
        !ChineseNamePatterns.nonNamePhrases.contains(name) &&
        !ChineseNamePatterns.nonNamePairs.contains(name) &&
        isValidName(name)
    }

    private func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let chars = Array(trimmed)

        guard trimmed.count >= 2 && trimmed.count <= 4 else { return false }
        guard trimmed.unicodeScalars.allSatisfy({ CharacterSet.ideographicCharacters.contains($0) }) else { return false }

        if ChineseNamePatterns.nonNamePhrases.contains(trimmed) { return false }
        if ChineseNamePatterns.nonNamePairs.contains(trimmed) { return false }

        if trimmed.count == 2 {
            if !firstCharIsSurname(trimmed) && !ChineseNamePatterns.namePrefixes.contains(String(trimmed.prefix(1))) {
                return false
            }
            if ChineseNamePatterns.nonNamePairs.contains(trimmed) { return false }
            if let last = trimmed.last, ChineseNamePatterns.nonNameSuffix2Chars.contains(last) { return false }
            return true
        }

        let hasSingleSurname = firstCharIsSurname(trimmed)
        let hasCompoundSurname = trimmed.count >= 3 && ChineseNamePatterns.compoundSurnames.contains(String(trimmed.prefix(2)))
        guard firstCharIsSurname(trimmed) || trimmed.count >= 3 && ChineseNamePatterns.compoundSurnames.contains(String(trimmed.prefix(2))) else { return false }

        for i in 1..<chars.count {
            if ChineseNamePatterns.strongRejectChars.contains(chars[i]) { return false }
        }

        if chars.count == 3 {
            if ChineseNamePatterns.grammarRejectChars.contains(chars[2]) { return false }
            if ChineseNamePatterns.weakRejectChars.contains(chars[2]) { return false }
        }
        if chars.count >= 4 {
            for i in 2..<chars.count {
                if ChineseNamePatterns.weakRejectChars.contains(chars[i]) { return false }
            }
        }

        return true
    }

    private func firstCharIsSurname(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        return ChineseNamePatterns.singleSurnames.contains(String(first))
    }

    // MARK: - Phase 2: Frequency Counting

    private func countFrequencies(text: String, candidates: Set<String>) -> [String: Int] {
        let ac = ACAutomaton()
        for name in candidates where !ChineseNamePatterns.stopWords.contains(name) && name.count >= 2 {
            ac.insert(name)
        }
        let rawCounts = ac.search(text)
        return rawCounts.filter { $0.value >= config.minFrequency }
    }

    // MARK: - Phase 3: Profile Building

    private func buildProfiles(from frequencies: [String: Int], text: String, originalText: String) -> [ExtractedCharacter] {
        let sorted = frequencies.sorted { $0.value > $1.value }
        let topNames = sorted.prefix(config.maxCharacters).map { $0.key }

        var characters: [ExtractedCharacter] = []

        for name in topNames {
            var char = ExtractedCharacter(name: name)
            char.confidence = min(Double(frequencies[name] ?? 1) / 100.0, 1.0)

            let contexts = gatherContext(for: name, in: originalText, maxLength: config.maxContextLength)
            inferAttributes(for: &char, from: contexts)

            char.sampleLines = extractSampleLines(for: name, from: originalText, maxSamples: 3)

            characters.append(char)
        }

        return characters
    }

    private func gatherContext(for name: String, in text: String, maxLength: Int) -> [String] {
        var contexts: [String] = []
        let paragraphs = text.components(separatedBy: .newlines)

        for para in paragraphs where para.contains(name) {
            contexts.append(para)
            if contexts.count * 200 >= maxLength { break }
        }

        let sentences = text.split { "。！？.!?".contains($0) }.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        for sent in sentences where sent.contains(name) && sent.count < 200 {
            contexts.append(sent)
            if contexts.count >= 50 { break }
        }

        return Array(contexts.prefix(100))
    }

    private func inferAttributes(for char: inout ExtractedCharacter, from contexts: [String]) {
        var maleVotes = 0, femaleVotes = 0
        var youngVotes = 0, oldVotes = 0
        var cheerfulVotes = 0, angryVotes = 0, sadVotes = 0

        for context in contexts {
            if containsAny(context, keywords: ["小姐", "姑娘", "师妹", "师姐", "奶奶", "娘", "公主", "女侠", "女士", "夫人", "太太", "妹妹", "女儿", "女眷", "女子", "女人", "母亲", "母亲", "妈妈", "妈", "她", "她们", "女生", "女孩", "少女", "姑娘家"]) { femaleVotes += 3 }
            if containsAny(context, keywords: ["先生", "公子", "兄", "少爷", "师兄", "师弟", "陛下", "王爷", "将军", "兄台", "掌门", "教主", "帮主", "前辈", "兄台", "贤弟", "师兄", "师弟", "少侠", "哥哥", "大哥", "大叔", "大爷", "伯伯", "叔叔", "老爷", "父亲", "爸爸", "爹", "儿子", "儿子", "他", "他们", "他", "男人", "男子", "汉子", "大叔", "大伯"]) { maleVotes += 3 }

            if context.contains("她") { femaleVotes += 1 }
            if context.contains("他") { maleVotes += 1 }

            if containsAny(context, keywords: ["老", "年迈", "白发", "老者", "老人家", "婆婆", "姥姥", "爷爷", "姥爷", "年长", "老者", "老头", "老太"]) { oldVotes += 2 }
            if containsAny(context, keywords: ["年轻", "少年", "少女", "青涩", "稚嫩", "年幼", "小小", "幼小", "孩童", "稚子"]) { youngVotes += 2 }

            if containsAny(context, keywords: ["笑", "开心", "欢喜", "大笑", "哈哈", "呵呵", "嘻嘻"]) { cheerfulVotes += 1 }
            if containsAny(context, keywords: ["怒", "吼", "骂", "愤", "恨", "暴怒", "大怒", "怒吼", "暴躁"]) { angryVotes += 1 }
            if containsAny(context, keywords: ["叹", "悲", "泣", "哭", "哽咽", "伤心", "难过", "凄凉", "悲伤", "泪"]) { sadVotes += 1 }
        }

        if femaleVotes == 0 && maleVotes == 0 {
            char.gender = "未知"
        } else {
            char.gender = femaleVotes > maleVotes ? "女性" : "男性"
        }

        if youngVotes == 0 && oldVotes == 0 {
            char.age = "青年"
        } else {
            char.age = youngVotes > oldVotes ? "少年" : "年长"
        }

        let maxTone = max(cheerfulVotes, angryVotes, sadVotes)
        if maxTone == 0 {
            char.tone = "平稳"
            char.style = "neutral"
            char.rate = 0
            char.pitch = 0
        } else if maxTone == cheerfulVotes {
            char.tone = "轻松"
            char.style = "cheerful"
            char.rate = 5
            char.pitch = 5
        } else if maxTone == angryVotes {
            char.tone = "激昂"
            char.style = "angry"
            char.rate = 15
            char.pitch = 10
        } else {
            char.tone = "温柔"
            char.style = "sad"
            char.rate = -10
            char.pitch = -5
        }
    }

    private func extractSampleLines(for name: String, from text: String, maxSamples: Int) -> [String] {
        var samples: [String] = []
        let paragraphs = text.components(separatedBy: .newlines)

        for para in paragraphs where para.contains(name) {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 10 && trimmed.count < 200 {
                samples.append(trimmed)
                if samples.count >= maxSamples { break }
            }
        }
        return samples
    }

    // MARK: - Phase 4: Narrator Identification

    private func identifyNarrator(from characters: [ExtractedCharacter], text: String) -> ExtractedCharacter? {
        for char in characters {
            if char.name == "旁白" || char.name.contains("旁白") {
                var narrator = char
                narrator.isNarrator = true
                narrator.tone = "平稳"
                narrator.style = "neutral"
                narrator.rate = 0
                narrator.pitch = 0
                return narrator
            }
        }

        var narrator = ExtractedCharacter(name: "旁白")
        narrator.isNarrator = true
        narrator.gender = "未知"
        narrator.age = "未知"
        narrator.tone = "平稳"
        narrator.style = "neutral"
        narrator.rate = 0
        narrator.pitch = 0
        narrator.confidence = 0.9
        return narrator
    }

    // MARK: - Phase 5: Voice Assignment

    private func assignVoices(to characters: [ExtractedCharacter], narrator: ExtractedCharacter?) -> [ExtractedCharacter] {
        var result = characters
        let maleVoices = ["zh-CN-YunxiNeural", "zh-CN-YunjianNeural", "zh-CN-YunzeNeural"]
        let femaleVoices = ["zh-CN-XiaoxiaoNeural", "zh-CN-XiaoyiNeural", "zh-CN-XiaohanNeural", "zh-CN-XiaomoNeural"]
        let neutralVoices = ["zh-CN-XiaoxiaoNeural", "zh-CN-YunxiNeural"]

        var maleIdx = 0, femaleIdx = 0

        for i in result.indices {
            if result[i].isNarrator {
                result[i].voiceID = "zh-CN-XiaoxiaoNeural"
                continue
            }

            let gender = result[i].gender
            if gender == "男性" || (gender == "未知" && maleIdx <= femaleIdx) {
                result[i].voiceID = maleVoices[maleIdx % maleVoices.count]
                maleIdx += 1
            } else if gender == "女性" || (gender == "未知" && femaleIdx < maleIdx) {
                result[i].voiceID = femaleVoices[femaleIdx % femaleVoices.count]
                femaleIdx += 1
            } else {
                result[i].voiceID = neutralVoices[0]
            }
        }

        return result
    }

    private func containsAny(_ text: String, keywords: [String]) -> Bool {
        for kw in keywords {
            if text.contains(kw) { return true }
        }
        return false
    }

    private func extractDialogues(from text: String) -> [DialogueSegment] {
        var results: [DialogueSegment] = []
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)

        for pattern in RegexPatterns.quoteExtract.compactMap({ $0 }) {
            pattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
                guard let m = match, m.numberOfRanges > 1 else { return }
                guard let r = Range(m.range(at: 1), in: text) else { return }
                let content = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return }
                results.append(DialogueSegment(speaker: nil, content: content, range: r))
            }
        }
        return results
    }
}