import Foundation
import UIKit

// MARK: - Haptic Feedback
enum HapticManager {
    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard UserDefaults.standard.object(forKey: "enableHaptics") as? Bool ?? true else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    @MainActor
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard UserDefaults.standard.object(forKey: "enableHaptics") as? Bool ?? true else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    @MainActor
    static func selection() {
        guard UserDefaults.standard.object(forKey: "enableHaptics") as? Bool ?? true else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

extension String {
    func regexGroups(pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let matches = regex.matches(in: self, options: [], range: NSRange(location: 0, length: utf16.count))
        return matches.map { match in
            (0..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: self) else { return nil }
                return String(self[range])
            }
        }
    }

    func firstMatch(regex pattern: String) -> [String]? {
        return regexGroups(pattern: pattern).first
    }

    func chunked(into length: Int) -> [String] {
        guard length > 0, length < utf16.count else { return [self] }
        var chunks: [String] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: length, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[start..<end]))
            start = end
        }
        return chunks
    }

    func contextAround(_ substring: String, radius: Int) -> String {
        guard let range = range(of: substring) else { return self }
        let lower = index(range.lowerBound, offsetBy: -radius, limitedBy: startIndex) ?? startIndex
        let upper = index(range.upperBound, offsetBy: radius, limitedBy: endIndex) ?? endIndex
        return String(self[lower..<upper])
    }

    /// 稳定哈希值，用于缓存键（不依赖进程哈希种子）
    var stableHash: String {
        var hasher = StableHasher()
        hasher.combine(self)
        return String(hasher.finalize(), radix: 16, uppercase: false).leftPad(to: 16, with: "0")
    }
}

private struct StableHasher: Hashable {
    private var state: UInt64 = 1469598103934665603 // FNV offset basis
    mutating func combine(_ value: String) {
        for byte in value.utf8 {
            state ^= UInt64(byte)
            state &*= 1099511628211 // FNV prime
        }
    }
    func finalize() -> UInt64 { state }
}

extension String {
    func leftPad(to length: Int, with character: Character) -> String {
        if count >= length { return self }
        return String(repeating: character, count: length - count) + self
    }
}

extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        var existing = components.queryItems ?? []
        existing.append(contentsOf: queryItems)
        components.queryItems = existing
        return components.url ?? self
    }
}

struct OrderedSet<Element: Hashable>: Collection, Equatable, Hashable {
    private var array: [Element]
    private var set: Set<Element>

    init() {
        array = []
        set = []
    }

    init(_ elements: some Sequence<Element>) {
        array = []
        set = []
        for element in elements {
            append(element)
        }
    }

    var startIndex: Int { array.startIndex }
    var endIndex: Int { array.endIndex }

    var isEmpty: Bool { array.isEmpty }
    var count: Int { array.count }

    func index(after i: Int) -> Int { array.index(after: i) }
    subscript(position: Int) -> Element { array[position] }

    mutating func append(_ element: Element) {
        guard !set.contains(element) else { return }
        set.insert(element)
        array.append(element)
    }

    func contains(_ element: Element) -> Bool {
        set.contains(element)
    }

    func firstIndex(of element: Element) -> Int? {
        array.firstIndex(of: element)
    }
}
