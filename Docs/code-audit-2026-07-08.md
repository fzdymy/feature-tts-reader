# 项目代码安全与稳定性审计

日期：2026-07-08

概述：
- 本次审计对仓库 Sources/FeatureTTSReaderApp 下的 Swift 源码进行了静态扫描与风险识别，重点查找会导致崩溃（crash）、未定义行为（UB）、竞态（race）或数据丢失的问题。
- 本文档给出按严重性归类的发现（P0/P1/P2）、根因简述与最小化修复建议（不修改代码，仅建议）。

=== 关键风险 Top-5（优先处理） ===

1. `Sources/FeatureTTSReaderApp/CosyVoiceService.swift` — 强制解包 `activeDownloadTask!.value`（P0）
   - 原因：并发路径可能将 shared 可选任务设为 `nil` 后再强制解包，导致马上崩溃。
   - 建议：捕获 Task 到局部变量并 await（例如 `let t = Task { ... }; activeDownloadTask = t; try await t.value`），或在解包前做原子检查与同步。

2. `Sources/FeatureTTSReaderApp/Services.swift` — 存储并多处 resume 相同 `CheckedContinuation`（P0）
   - 原因：多个控制流（`stop()`, `finishPlayback()` 等）可同时或先后 resume 已 resume 的 continuation，double-resume 会触发 UB/崩溃。
   - 建议：在 resume 前原子交换并清除 continuation（`let c = playbackContinuation; playbackContinuation = nil; c?.resume()`），或换用 `AsyncStream`/单拥有者 `withCheckedContinuation` 模式。

3. `Sources/FeatureTTSReaderApp/AdvancedAudioPlaybackController.swift` — 同续 `playbackContinuation` 双重 resume 风险（P0）
   - 建议同上：确保 resume-and-clear 原子化，避免在不同路径中重复 resume。

4. `Sources/FeatureTTSReaderApp/Models.swift` — `BookChapter` / `Book` 的自定义 `Codable` 丢弃 `text` 字段（P1，数据丢失）
   - 原因：encode/decode 未包含 `text`，序列化/反序列化会丢失章节/书文本，运行时可能出现空文本导致逻辑异常。
   - 建议：将 `text` 纳入 Codable，或改为持久化到独立文件并序列化参考路径；在设计上明确是否为有意行为并记录格式文档。

5. `Sources/FeatureTTSReaderApp/BertSpeakerDetector.swift` — 标注 `@unchecked Sendable` 却持有 `MLModel` 并做并发调用（P1）
   - 原因：CoreML `MLModel` 并非天然线程安全，未经同步的并发访问可能导致数据竞争或崩溃。
   - 建议：改为 actor/串行队列保护模型调用，或在类型上移除 `@unchecked Sendable` 并限制调用路径。

=== 全量发现（按文件） ===

- Sources/FeatureTTSReaderApp/CosyVoiceService.swift
  - ≈320-356 — P0 — 强制解包 `activeDownloadTask!.value`：竞态导致 NPE/崩溃。见 Top1 建议。
  - ≈1088-1160 — P1 — `_DownloadDelegate` 使用手动存储 continuation、临时 `_tempURL` 与 `_error`：存在 race 与 double-resume 风险；delegate 与等待者间的顺序依赖脆弱。
  - 多处全局/非隔离可变状态（`nonisolated(unsafe)`）— P1 — 共享可变状态未统一加锁/隔离，存在数据竞争。
  - ≈720-940 — P1 — 二进制 ZIP/TAR 解析对 `Data` 的直接索引（`data[off+N]`）缺少充分边界检查，碰到损坏/截断文件会越界崩溃。
  - ≈580-700 — P1 — `URLSession` + delegate 生命周期与取消路径（invalidate/cancel）在复杂 async 流中可能造成 delegate 被释放或回调未被正确处理；应保证 delegate 在 result 完成前被强引用。
  - ≈1080-1160 — P2 — 临时文件复制使用 `try?` 抑制错误，可能将无效 URL 传回给 caller，建议传播 I/O 错误。

- Sources/FeatureTTSReaderApp/Services.swift
  - ≈1-230 — P0 — `playbackContinuation` 被多处 resume；double-resume/竞态导致 UB/崩溃。建议原子清除并 resume，或改设计。

- Sources/FeatureTTSReaderApp/AdvancedAudioPlaybackController.swift
  - ≈1-420 — P0 — 与 `Services.swift` 相同的 continuation 问题。
  - ≈120-220 — P2 — `AVAudioFile(forReading:)` 失败分支使用递归跳过文件，存在无限/深度递归风险。建议改为迭代。

- Sources/FeatureTTSReaderApp/Store.swift
  - ≈82-96 — P2 — 使用 `bookChaptersCache.keys.first!` 强制解包，虽在逻辑上应有元素但仍不安全；建议使用 `if let` 安全移除或维护确定性的淘汰顺序。

- Sources/FeatureTTSReaderApp/Models.swift
  - P1 — 自定义 Codable 未保存 `text` 字段（数据丢失），应明确持久化策略或修复 CodingKeys。

- Sources/FeatureTTSReaderApp/Extensions.swift
  - ≈64-78 — P1 — `OrderedSet` 的 `subscript(position: Int)` 直接索引数组无边界检查，越界会崩溃；建议添加范围检查或返回可选。

- Sources/FeatureTTSReaderApp/BertSpeakerDetector.swift
  - P1 — `@unchecked Sendable` + `MLModel` 并发访问风险；应序列化模型调用或加隔离。

- 其它注意项（P2 / 可改进）
  - Embedding 编码格式：部分代码以 JSON 保存 [Float]，有历史上曾用 raw binary 的记录。若代码路径混用两种格式，解码会失败。建议统一格式并在解码时做 defensive 校验。
  - 文件/流解析中多处 `try?` 或吞掉错误的用法，会隐藏真实失败原因。建议在关键路径上返回/记录错误以便上层处理。

=== 优先级与建议行动清单（短期） ===

1. 立即修复 double-resume 与 stored continuation 问题（P0）
   - 文件：`Services.swift`、`AdvancedAudioPlaybackController.swift`、以及任何持有 `CheckedContinuation` 的模块。
   - 目标：保证 resume 前按原子方式清空 continuation，或使用拥有者模式 `withCheckedContinuation` 并避免长期存储 continuation。

2. 修复 `CosyVoiceService.swift` 的 `activeDownloadTask` 强制解包与 delegate-继续体竞态（P0/P1）
   - 捕获 Task 到局部变量后 await；重构 delegate → continuation 桥接以确保单一 resume 路径。

3. 添加边界检查到所有低层二进制解析（ZIP/TAR）代码（P1）
   - 检查每次 `data[offset + n]` 前的范围；对损坏/截断数据返回明确错误而非越界访问。

4. 恢复/保留 `Book`/`BookChapter` 文本在序列化中（P1）
   - 评估是否因体积刻意排除 `text`，若不是则将其加入 Codable；若是，则改为持久化外部文件并在模型中保留引用路径。

5. 对 `MLModel` / CoreML 调用做序列化保护（P1）
   - 将 `BertSpeakerDetector` 限定为 actor 或使用串行队列。

=== 交付物与后续建议 ===

- 本次审计已生成本文件，列出关键问题与修复建议（不修改代码）。
- 如果需要，我可以按照优先级：先生成补丁草案（代码修改 PR），或仅生成更详细的单个文件修复说明供开发者实施。

若要我继续：请选择一项操作
- 生成针对 P0 问题的修复补丁草案（代码修改 PR）
- 针对 P1 问题生成更详尽的变更清单与单个文件代码片段
- 停止，保存审计文档

=== 针对你提供的崩溃日志的补充分析 ===

结论（简短）：最可能的原因是播放/恢复路径中存在对同一 `CheckedContinuation` 的重复 resume（double-resume）或 resume-after-deinit 导致的未定义行为（UB），结合程序启动与恢复流程的日志，这一问题优先级最高并极有可能触发你看到的崩溃。

证据要点：
- 审计中发现 `Services.swift` 与 `AdvancedAudioPlaybackController.swift` 都以对象属性方式保存 `playbackContinuation` 并在 `stop()`/`finishPlayback()`/恢复播放路径中 resume，此类模式在并发或重入场景下会导致 double-resume，从而崩溃。
- 你提供的日志显示初始化完成后立即进入恢复播放与引擎启动（`init_restore_playback_done` / `bookshelf_engine_started`），并伴随视图生命周期多次触发（重复的 `bookshelf_body_start`），这些场景容易造成恢复与取消等路径重入并并发操作 continuation。

如何验证（快速）：
1. 查看完整 crash report 的 stack trace，寻找调用栈中 `resume`、`withCheckedContinuation`、`playFilesAndWait`、`finishPlayback` 等符号；若栈顶或线程栈含这些符号，几乎可以确认为 double-resume。
2. 在 `Services.swift` / `AdvancedAudioPlaybackController.swift` 中对所有 resume 点临时加入日志：在 resume 前打印 timestamp + caller id，并改为先 `let c = playbackContinuation; playbackContinuation = nil; c?.resume()`；观察是否能重现并在日志中看到重复 resume 的迹象。

临时缓解（可快速验证）：
- 在所有 resume 点按原子方式取出并清空 continuation 再 resume（见上文代码片段），这能立即避免 double-resume 导致的崩溃，便于确认问题根源。

长期修复建议：
- 避免长期存储 `CheckedContinuation`。使用 `AsyncStream`、`AsyncChannel` 或把 `withCheckedContinuation` 的生命周期限定为单一调用者（single-owner pattern）。
- 对关键并发边界施加 actor / 锁保护，避免 View 重入或 init/restore 期间的竞态。
- 同时修复 `CosyVoiceService` 中对共享 `Task` 的强制解包与 delegate→continuation 桥接问题，以降低启动/恢复期间的并发风险。

后续我可以：
- 直接生成一个临时补丁（在所有 resume 点做原子取出/清空再 resume）以供验证；或
- 搜索并列出仓库中所有 `withCheckedContinuation` / `playbackContinuation` 的使用点并生成逐点修复建议。

