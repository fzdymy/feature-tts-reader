import Foundation

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
        guard length > 0 else { return [self] }
        var chunks: [String] = []
        var current = self
        while !current.isEmpty {
            let endIndex = current.index(current.startIndex, offsetBy: min(length, current.count))
            chunks.append(String(current[current.startIndex..<endIndex]))
            current = String(current[endIndex...])
        }
        return chunks
    }

    func contextAround(_ substring: String, radius: Int) -> String {
        guard let range = range(of: substring) else { return self }
        let lower = index(range.lowerBound, offsetBy: -radius, limitedBy: startIndex) ?? startIndex
        let upper = index(range.upperBound, offsetBy: radius, limitedBy: endIndex) ?? endIndex
        return String(self[lower..<upper])
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
