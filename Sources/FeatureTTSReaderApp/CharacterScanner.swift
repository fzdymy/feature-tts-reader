import Foundation
import NaturalLanguage

/// Shared scanning pipeline used by both Store.scanCharacters() and CharacterAssignmentView.startScan().
/// Extracts the common orchestration logic from CharacterAnalyzer primitives.
struct CharacterScanner {
    struct Config {
        var maxResults: Int = 12
        var useNLValidation: Bool = true
        var includeGraph: Bool = false
        var chunkSize: Int = 30_000
        var acFreqLimit: Int = 500_000
    }

    struct Result {
        var characters: [CharacterProfile]
        var edges: [RelationshipEdge]
    }

    static func scan(text: String, config: Config = Config(), voices: [VoiceItem] = [],
                     defaultSensitivity: Int = 50, bookID: UUID? = nil) async -> Result
    {
        let analyzer = CharacterAnalyzer()
        let raw = text.replacingOccurrences(of: "\r", with: "\n")

        // 1. Regex candidate extraction (chunked to avoid blocking)
        let candidates = await extractCandidates(from: raw, chunkSize: config.chunkSize, analyzer: analyzer)
        var candidateScores: [String: Int] = [:]
        for n in candidates { candidateScores[n, default: 0] += 1 }

        // 2. AC automaton frequency
        let freqResult = await frequencyAnalysis(text: raw, candidates: candidateScores,
                                                   limit: config.acFreqLimit, analyzer: analyzer)
        let sorted = freqResult.keys.sorted { freqResult[$0, default: 0] > freqResult[$1, default: 0] }

        // 3. Filter by looksLikeRealName + high-frequency pass
        var names = OrderedSet<String>()
        for n in sorted {
            let freq = freqResult[n, default: 0]
            guard CharacterAnalyzer.looksLikeRealName(n) ||
                  CharacterAnalyzer.titleSuffixes.contains(where: { n.hasSuffix($0) }) ||
                  (freq >= 10 && n.count >= 2 && n.count <= 4 && !analyzer.isStopWord(n))
            else { continue }
            names.append(n)
        }

        // 4. Prefix deduplication (keep higher-frequency name)
        let ranked = freqResult.sorted { $0.value > $1.value }
        var dedup = OrderedSet<String>()
        for (name, _) in ranked where names.contains(name) {
            let isPrefix = dedup.contains { $0.count >= 2 && name.hasPrefix($0) && $0 != name }
            if !isPrefix { dedup.append(name) }
        }
        names = dedup

        // 5. NL tagger validation
        if config.useNLValidation {
            let nlValidated = analyzer.validateWithNL(text: raw, candidates: Set(names))
            if !nlValidated.isEmpty { names = OrderedSet(names.filter { nlValidated.contains($0) }) }
        }

        // 6. Alias resolution
        let resolved = CharacterAnalyzer.resolveAliases(Array(names))
        let allAliases = Set(resolved.flatMap { $0.aliases })
        let canonicalNames = resolved.map { $0.canonical }.filter { !allAliases.contains($0) }

        // 7. Attribute analysis for top characters
        let narratorIndicators = detectNarratorPatterns(in: raw)
        var profiles: [CharacterProfile] = []
        let contextLimit = min(config.acFreqLimit, raw.count)
        let contextText = raw.prefix(contextLimit)

        for resolvedName in resolved.prefix(config.maxResults) {
            let name = resolvedName.canonical
            let aliases = resolvedName.aliases
            guard let range = contextText.range(of: name) else { continue }
            let ctxStart = contextText.index(range.lowerBound, offsetBy: -50, limitedBy: contextText.startIndex) ?? contextText.startIndex
            let ctxEnd = contextText.index(range.upperBound, offsetBy: 150, limitedBy: contextText.endIndex) ?? contextText.endIndex
            let ctx = String(contextText[ctxStart..<ctxEnd])
            let attrs = analyzer.analyzeAttributes(for: name, context: ctx)
            let isNarrator = isNarratorPattern(name: name, context: ctx, indicators: narratorIndicators)
            profiles.append(CharacterProfile(
                id: UUID(), name: name, aliases: aliases, bookID: bookID,
                gender: attrs.gender, age: attrs.age, tone: attrs.baseTone,
                voice: isNarrator ? "" : defaultVoice(for: attrs.gender, voices: voices),
                rate: attrs.baseRate, pitch: attrs.basePitch, style: attrs.baseStyle,
                sensitivity: defaultSensitivity, isNarrator: isNarrator,
                role: isNarrator ? .narrator : .character
            ))
        }

        // Ensure narrator exists
        if !profiles.contains(where: { $0.isNarrator }) {
            profiles.insert(CharacterProfile(
                id: UUID(), name: "旁白", gender: "未知", age: "未知", tone: "平稳",
                voice: defaultVoice(for: "未知", voices: voices),
                rate: 0, pitch: 0, style: "neutral", sensitivity: defaultSensitivity,
                isNarrator: true, role: .narrator
            ), at: 0)
        }

        // 8. Relationship graph
        var edges: [RelationshipEdge] = []
        if config.includeGraph && raw.count > 10000 {
            edges = analyzer.buildRelationshipGraph(text: raw, characterNames: profiles.flatMap { [$0.name] + $0.aliases })
        }

        return Result(characters: profiles, edges: edges)
    }

    // MARK: - Private

    private static func extractCandidates(from text: String, chunkSize: Int, analyzer: CharacterAnalyzer) async -> Set<String> {
        let nsText = text as NSString
        let totalLen = nsText.length
        let totalChunks = max(1, (totalLen + chunkSize - 1) / chunkSize)
        var allNames = Set<String>()
        for i in 0..<totalChunks {
            let start = i * chunkSize
            let end = min(start + chunkSize, totalLen)
            let chunk = nsText.substring(with: NSRange(location: start, length: end - start))
            let names = await Task.detached(priority: .userInitiated) {
                analyzer.extractDialogueNames(from: chunk)
            }.value
            for n in names { allNames.insert(n) }
            await Task.yield()
        }
        return allNames
    }

    private static func frequencyAnalysis(text: String, candidates: [String: Int], limit: Int, analyzer: CharacterAnalyzer) async -> [String: Int] {
        let freqText = String(text.prefix(limit))
        return await Task.detached(priority: .userInitiated) {
            analyzer.countWithAC(text: freqText, candidates: candidates)
        }.value
    }

    private static func isNarratorPattern(name: String, context: String, indicators: Set<String>) -> Bool {
        if indicators.contains(name) { return true }
        let keywords = ["叙述", "讲述", "旁白", "作者", "笔者"]
        return keywords.contains { name.contains($0) }
    }

    private static func detectNarratorPatterns(in text: String) -> Set<String> {
        let patterns = ["只见", "这时", "此时", "忽然", "突然", "原来", "却说", "且说", "话说", "正是"]
        return Set(patterns.filter { text.contains($0) })
    }

    private static func defaultVoice(for gender: String, voices: [VoiceItem]) -> String {
        let target: VoiceGender = (gender == "男" || gender == "男性") ? .male : .female
        return voices.first(where: { $0.gender == target })?.id ?? voices.first?.id ?? ""
    }
}
