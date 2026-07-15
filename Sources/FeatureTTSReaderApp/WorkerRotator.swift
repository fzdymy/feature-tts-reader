import Foundation

/// AI Worker 轮询调度器：按章节轮询，分摊账号配额
actor WorkerRotator {
    private var configs: [AIWorkerConfig] = []
    private var currentIndex = 0
    private var chapterCounter = 0
    private var rotationInterval = 5
    private var maxSlicesPerWorker = 10
    private var failedWorkerIDs: Set<UUID> = []
    private var failureCooldown: [UUID: Date] = [:]

    func configure(with configs: [AIWorkerConfig], interval: Int? = nil, maxSlices: Int = 10) {
        self.configs = configs
        let userInterval = UserDefaults.standard.object(forKey: "workerRotationInterval") as? Int
        self.rotationInterval = max(1, interval ?? userInterval ?? 5)
        self.maxSlicesPerWorker = max(1, maxSlices)
    }

    nonisolated func saveInterval(_ interval: Int) {
        UserDefaults.standard.set(interval, forKey: "workerRotationInterval")
    }

    /// 获取下一个健康的 Worker。chapterIndex 用于计算轮询边界
    func next(chapterIndex: Int, sliceCount: Int = 0) -> AIWorkerConfig? {
        let now = Date()
        // Recover workers after 5 minute cooldown
        for id in failedWorkerIDs {
            if let cooldown = failureCooldown[id], now.timeIntervalSince(cooldown) > 300 {
                failedWorkerIDs.remove(id)
                failureCooldown.removeValue(forKey: id)
            }
        }

        let enabled = sortByPriority(configs.filter { $0.isEnabled && !failedWorkerIDs.contains($0.id) })
        guard !enabled.isEmpty else {
            let all = sortByPriority(configs)
            return all.first(where: { $0.isDefault }) ?? all.first
        }

        if chapterCounter >= rotationInterval || sliceCount > maxSlicesPerWorker {
            currentIndex = (currentIndex + 1) % enabled.count
            chapterCounter = 0
        }
        chapterCounter += 1
        return enabled[currentIndex % enabled.count]
    }

    /// 标记 Worker 失败（5 分钟冷却后自动恢复）
    func markFailure(_ id: UUID) {
        failedWorkerIDs.insert(id)
        failureCooldown[id] = Date()
    }

    /// 标记 Worker 恢复
    func markSuccess(_ id: UUID) {
        failedWorkerIDs.remove(id)
        failureCooldown.removeValue(forKey: id)
    }

    private func sortByPriority(_ cs: [AIWorkerConfig]) -> [AIWorkerConfig] {
        cs.sorted { $0.priority > $1.priority }
    }

    /// 重置状态（切换书籍时调用）
    func reset() {
        currentIndex = 0
        chapterCounter = 0
        failedWorkerIDs.removeAll()
        failureCooldown.removeAll()
    }
}
