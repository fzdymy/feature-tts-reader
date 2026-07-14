import Foundation

/// 角色别名管理器：合并/分离/重命名/删除/归一化
actor CharacterAliasManager {
    private var aliases: [String: String] = [:]  // 别名 → 主名

    func setAliases(_ dict: [String: String]) { aliases = dict }
    func allAliases() -> [String: String] { aliases }

    /// 解析别名 → 主名（最多 5 层，防循环）
    func resolve(_ name: String) -> String {
        var current = name
        var visited = Set<String>()
        var depth = 0
        while let next = aliases[current], next != current, !visited.contains(current), depth < 5 {
            visited.insert(current)
            current = next
            depth += 1
        }
        return current
    }

    /// 获取指定主角色下的所有别名
    func aliasesOf(_ main: String) -> [String] {
        aliases.filter { $0.value == main }.map(\.key).sorted()
    }

    /// 合并：source → target
    func merge(source: String, into target: String) {
        guard source != target, !source.isEmpty, !target.isEmpty else { return }
        guard aliases[target] == nil else { return }
        aliases.removeValue(forKey: source)
        let sourceAliases = aliases.filter { $0.value == source }.map(\.key)
        for a in sourceAliases { aliases[a] = target }
        aliases[source] = target
    }

    /// 分离：将指定别名独立
    func split(_ alias: String) {
        aliases.removeValue(forKey: alias)
    }

    /// 删除角色关联的所有别名
    func removeAll(for main: String) {
        let toRemove = aliases.filter { $0.value == main }.map(\.key)
        for a in toRemove { aliases.removeValue(forKey: a) }
        if aliases[main] != nil { aliases.removeValue(forKey: main) }
    }

    /// 重命名角色（更新别名映射中的键和值）
    func rename(old: String, to new: String) {
        aliases[new] = aliases.removeValue(forKey: old)
        let toUpdate = aliases.filter { $0.value == old }.map(\.key)
        for a in toUpdate { aliases[a] = new }
    }

    /// 角色名归一化：移括号注释、trim、空格归并
    static func normalizeSpeakerName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 移除括号注释：李华（主角）→ 李华
        if let paren = name.firstIndex(of: "（") {
            name = String(name[..<paren])
        }
        if let paren = name.firstIndex(of: "(") {
            name = String(name[..<paren])
        }
        // 移除多余空格：李  华 → 李华
        name = name
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined()
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
