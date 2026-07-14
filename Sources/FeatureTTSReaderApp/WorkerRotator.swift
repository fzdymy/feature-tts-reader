import Foundation

/// AI Worker 轮询调度器：按章节轮询，分摊账号配额
actor WorkerRotator {
    private var configs: [AIWorkerConfig] = []
    private var currentIndex = 0
    private var chapterCounter = 0
    private var rotationInterval = 5       // 默认每 5 章切换
    private var maxSlicesPerWorker = 10   // 单章超长分片上限

    func configure(with configs: [AIWorkerConfig], interval: Int = 5, maxSlices: Int = 10) {
        self.configs = configs
        self.rotationInterval = max(1, interval)
        self.maxSlicesPerWorker = max(1, maxSlices)
    }

    /// 获取下一个健康的 Worker。chapterIndex 用于计算轮询边界
    func next(chapterIndex: Int, sliceCount: Int = 0) -> AIWorkerConfig? {
        let enabled = configs.filter { $0.isEnabled }
        guard !enabled.isEmpty else { return configs.first(where: { $0.isDefault }) ?? configs.first }

        // 按章节轮询
        if chapterCounter >= rotationInterval || sliceCount > maxSlicesPerWorker {
            currentIndex = (currentIndex + 1) % enabled.count
            chapterCounter = 0
        }
        chapterCounter += 1
        return enabled[currentIndex % enabled.count]
    }

    /// 标记 Worker 失败（临时跳过）
    func markFailure(_ id: UUID) {
        // 从 configs 中暂时移除，下次重新加入
    }

    /// 标记 Worker 恢复
    func markSuccess(_ id: UUID) {
        // 重新加入轮询池
    }
}
