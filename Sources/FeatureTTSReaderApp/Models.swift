import Foundation

struct BookChapter: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let text: String

    var preview: String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 120 {
            return cleaned
        }
        return String(cleaned.prefix(120)) + "..."
    }
}

struct CharacterProfile: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var gender: String
    var age: String
    var tone: String
    var voice: String
    var rate: Int
    var pitch: Int
    var style: String

    var info: String {
        [gender, age, tone].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct VoiceItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let locale: String
}

struct ScriptSegment: Identifiable, Hashable, Codable {
    let id: UUID
    let characterName: String
    let voice: String
    let rate: Int
    let pitch: Int
    let style: String
    let text: String
}

struct CharacterRecommendation: Identifiable, Hashable, Codable {
    let id: UUID
    var profile: CharacterProfile
    var count: Int
    var suggestedVoices: [VoiceItem]
}

struct ReaderState: Codable {
    var bookText: String
    var chapters: [BookChapter]
    var characters: [CharacterProfile]
    var scriptSegments: [ScriptSegment]
    var selectedChapterID: UUID?
    var apiEndpoint: String
    var apiKey: String
}
