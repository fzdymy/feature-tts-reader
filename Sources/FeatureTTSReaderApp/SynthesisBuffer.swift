import Foundation

/// 并发合成保序缓冲 actor：按 idx 顺序入队，确保播放顺序
actor SynthesisBuffer {
    var buffer: [Int: TTSQueueItem] = [:]
    var nextExpected = 0
    var flushedCount = 0
    var hasPlayedFirst = false
    let onReady: @Sendable ([TTSQueueItem]) async -> Void

    init(onReady: @Sendable @escaping ([TTSQueueItem]) async -> Void) {
        self.onReady = onReady
    }

    func insert(_ idx: Int, _ item: TTSQueueItem) async {
        buffer[idx] = item
        var ready: [TTSQueueItem] = []
        while let item = buffer.removeValue(forKey: nextExpected) {
            ready.append(item)
            nextExpected += 1
        }
        flushedCount += ready.count
        if !ready.isEmpty {
            await onReady(ready)
        }
    }

    func flushRemaining() async {
        let sorted = buffer.sorted { $0.key < $1.key }
        buffer.removeAll()
        flushedCount += sorted.count
        if !sorted.isEmpty {
            await onReady(sorted.map { $0.value })
        }
    }

    func markFirstPlayed() -> Bool {
        if hasPlayedFirst {
            return false
        }
        hasPlayedFirst = true
        return true
    }
}
