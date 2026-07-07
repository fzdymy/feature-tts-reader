import Foundation
import NaturalLanguage

/// Shared scanning pipeline used by both Store.scanCharacters() and CharacterAssignmentView.startScan().
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

        // ── Phase 1: Candidate extraction ──
        // Paragraph-level guard → regex locate → looksLikeRealName → NLTagger + surname fallback.
        // NLTagger validation is inline (not a separate kill-step like the old pipeline),
        // so web-novel names (萧炎, 林动) survive via surname fallback.
        let candidates = await Task.detached(priority: .userInitiated) {
            analyzer.extractCandidates(from: raw)
        }.value
        guard !candidates.isEmpty else { return fallbackResult(voices: voices, defaultSensitivity: defaultSensitivity, bookID: bookID) }

        // ── Phase 2: AC automaton frequency ──
        // Build ONE global AC automaton with the clean candidate set, scan full text once.
        // Filter out names appearing ≤1 time (likely false positives like 卫生间/高跟鞋).
        let freqResult = await Task.detached(priority: .userInitiated) {
            analyzer.countCharacterFrequencies(text: raw, candidates: candidates)
        }.value

        let sorted = freqResult.keys.sorted { freqResult[$0, default: 0] > freqResult[$1, default: 0] }
        var names = OrderedSet<String>()
        for n in sorted {
            let freq = freqResult[n, default: 0]
            guard CharacterAnalyzer.looksLikeRealName(n) ||
                  CharacterAnalyzer.titleSuffixes.contains(where: { n.hasSuffix($0) }) ||
                  (freq >= 10 && n.count >= 2 && n.count <= 4 && !analyzer.isStopWord(n))
            else { continue }
            names.append(n)
        }

        // Prefix deduplication
        let ranked = freqResult.sorted { $0.value > $1.value }
        var dedup = OrderedSet<String>()
        for (name, _) in ranked where names.contains(name) {
            let isPrefix = dedup.contains { $0.count >= 2 && name.hasPrefix($0) && $0 != name }
            if !isPrefix { dedup.append(name) }
        }
        names = dedup

        // Alias resolution
        let resolved = CharacterAnalyzer.resolveAliases(Array(names))

        // ── Phase 3: Multi-paragraph voting for attributes ──
        // No more "first occurrence ±150 chars" — aggregate ALL paragraphs
        // containing the character name for richer gender/age/tone cues.
        let narratorIndicators = detectNarratorPatterns(in: raw)
        var profiles: [CharacterProfile] = []

        for resolvedName in resolved.prefix(config.maxResults) {
            let name = resolvedName.canonical
            let aliases = resolvedName.aliases
            let attrs = analyzer.estimateAttributes(for: name, in: raw)
            let isNarrator = isNarratorPattern(name: name, context: "", indicators: narratorIndicators)
            profiles.append(CharacterProfile(
                id: UUID(), name: name, aliases: aliases,
                gender: attrs.gender, age: attrs.age, tone: attrs.baseTone,
                voice: isNarrator ? "" : defaultVoice(for: attrs.gender, voices: voices),
                rate: attrs.baseRate, pitch: attrs.basePitch, style: attrs.baseStyle,
                sensitivity: defaultSensitivity, isNarrator: isNarrator,
                role: isNarrator ? .narrator : .character, bookID: bookID
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

        // Relationship graph (unchanged)
        var edges: [RelationshipEdge] = []
        if config.includeGraph && raw.count > 10000 {
            edges = analyzer.buildRelationshipGraph(text: raw, characterNames: profiles.flatMap { [$0.name] + $0.aliases })
        }

        return Result(characters: profiles, edges: edges)
    }

    // MARK: - Private

    private static func fallbackResult(voices: [VoiceItem], defaultSensitivity: Int, bookID: UUID?) -> Result {
        let narrator = CharacterProfile(
            id: UUID(), name: "旁白", gender: "未知", age: "未知", tone: "平稳",
            voice: defaultVoice(for: "未知", voices: voices),
            rate: 0, pitch: 0, style: "neutral", sensitivity: defaultSensitivity,
            isNarrator: true, role: .narrator, bookID: bookID
        )
        return Result(characters: [narrator], edges: [])
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
        ""
    }
}
