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

修复建议：
- 避免长期存储 `CheckedContinuation`。使用 `AsyncStream`、`AsyncChannel` 或把 `withCheckedContinuation` 的生命周期限定为单一调用者（single-owner pattern）。
- 对关键并发边界施加 actor / 锁保护，避免 View 重入或 init/restore 期间的竞态。
- 同时修复 `CosyVoiceService` 中对共享 `Task` 的强制解包与 delegate→continuation 桥接问题，以降低启动/恢复期间的并发风险。

- 搜索并列出仓库中所有 `withCheckedContinuation` / `playbackContinuation` 的使用点并生成逐点修复建议。

=== 精确定位（文件 + 精确行号 + 触发条件与证据） ===

下面条目为本次审计中高优先级问题的精确定位，包含具体文件与近似/精确行号，以及导致崩溃或行为异常的触发条件与证据说明。

- `Sources/FeatureTTSReaderApp/CosyVoiceService.swift`
   - 行 299: `private var activeDownloadTask: Task<Void, Error>?`（声明）
   - 行 305-306 / 322-323 / 815-816: 多处 `activeDownloadTask?.cancel(); activeDownloadTask = nil`（取消/清理路径）
   - 行 346-350: 在 `ensureModel()` 启动下载时使用 `activeDownloadTask = Task { ... }` 并在 `defer { activeDownloadTask = nil }` 后 **行 350** 执行 `try await activeDownloadTask!.value`（强制解包 await）——触发条件：若在此期间其他路径执行 `activeDownloadTask = nil`（例如 `cancelDownload()` / 清理），则会发生强制解包 nil 导致崩溃。证据：文件中多处对同一可选 Task 的取消与清空（见上文行号），并存在强制解包点（行 350）。

- `Sources/FeatureTTSReaderApp/CosyVoiceService.swift` — 下载代理桥接
   - 行 1107: `private final class _DownloadDelegate: NSObject, URLSessionDownloadDelegate`（类起始）
   - 行 1116-1129: `var result: URL { get async throws { ... _continuation = c } }`（将 continuation 存为字段）
   - 行 1133-1140: `urlSession(_:didFinishDownloadingTo:)` 将 `_tempURL` 设值并调用 `_continuation?.resume(returning:)`，随后清空 `_continuation`。
   - 行 1144-1152: `urlSession(_:didCompleteWithError:)` 将 `_error` 设值并调用 `_continuation?.resume(throwing:)`，随后清空 `_continuation`。
   - 触发条件与证据：`_continuation` 被存储为 `nonisolated(unsafe)` 可变字段（行 1110），并在 delegate 回调与 async 等待者间依赖手动锁（`_lock`）的正确顺序；若有 ordering 问题或重复回调，可能发生 double-resume 或遗漏 resume（见类内 result/get 与 delegate callbacks 的实现行号）。

- `Sources/FeatureTTSReaderApp/CosyVoiceService.swift` — 非隔离全局/状态
   - 行 11-14: `nonisolated(unsafe) private var _proxyActive`、`_proxyCustomPrefix`、`_activeVariant`（可变全局，非隔离）
   - 行 105-128: 多个 `nonisolated static var` 访问器（activeVariant / modelDownloadURL / modelPageURL 等）
   - 触发条件与证据：这些可变全局在多个线程/任务间被读写（见文件中对 `activeVariant` 的读写与 `resetDownload()` 调用），若访问未统一同步，会出现数据竞争与未定义行为（见同文件多处对这些变量的直接读写）。

- `Sources/FeatureTTSReaderApp/CosyVoiceService.swift` — ZIP/TAR 低层解析越界风险
   - 行 720-805: `extractZip(archive:to:)` 的第一/第二次遍历里使用 `readLEU16/readLEU32` 并直接通过 `data[offset + N]` 索引数据块
   - 行 805: `private func readLEU16(_ data: Data, _ off: Int) -> UInt16 { UInt16(data[off]) | (UInt16(data[off+1]) << 8) }`
   - 触发条件与证据：在处理损坏或截断的 archive 时，若 header 校验或 hdrSize 计算不充分，会导致 `off+N` 超过 `data.count` 从而触发数组越界崩溃；证据为 `readLEU16/readLEU32` 的实现对 bounds 不做保护（见行 805 及邻近调用行 737-765）。

- `Sources/FeatureTTSReaderApp/Services.swift`（基于 `AVAudioPlayer` 的播放）
   - 行 18: `private var playbackContinuation: CheckedContinuation<Void, Never>?`（声明）
   - 行 97: `playFilesAndWait` 中将 continuation 存入属性：`playbackContinuation = cont`（赋值点）
   - 行 177-178: `stop()` 中 `playbackContinuation?.resume(); playbackContinuation = nil`（resume + clear）
   - 行 229-230: `finishPlayback()` 中 `playbackContinuation?.resume(); playbackContinuation = nil`（另一路径 resume + clear）
   - 触发条件与证据：在播放队列快速变化、用户操作或恢复流程（init/restore）期间，`stop()` 与 `finishPlayback()` 可能交替或并发调用，导致对同一 `CheckedContinuation` 的重复 `resume()`（double-resume）或在已释放上下文上 resume（resume-after-deinit），这会直接触发 UB/崩溃（见各 resume 位置行号）。

- `Sources/FeatureTTSReaderApp/AdvancedAudioPlaybackController.swift`（基于 AVAudioEngine 的播放）
   - 行 32: `private var playbackContinuation: CheckedContinuation<Void, Never>?`（声明）
   - 行 215: 在 `playFilesAndWait` / 等候路径中赋值 `self.playbackContinuation = cont`（赋值点）
   - 行 299-300 / 359-360: `playbackContinuation?.resume(); playbackContinuation = nil`（多处 resume）
   - 触发条件与证据：同 `Services.swift`，多路控制流可导致 double-resume；此外 `playNextSeamlessly()` 在 AVAudioFile 失败时递归重试（见行 140-170）可能加剧重入/递归导致的竞态。

- `Sources/FeatureTTSReaderApp/Store.swift` — `load_state_mainactor` 批量 @Published 赋值位置
   - 行 295: `Self.writeCrashMarker("load_state_mainactor")`
   - 行 300-306: `await MainActor.run { guard let state = decoded else { ... } ; Self.writeCrashMarker("ls_ma_guard_ok"); Self.writeCrashMarker("ls_ma_books"); books = state.books }`（`books = state.books` 紧随 `ls_ma_books`）
   - 证据与触发条件：你提供的 marker 日志中 `load_state_mainactor` 存在但 `ls_ma_books` 不存在，表明崩溃发生在 `load_state_mainactor` 内且早于 `ls_ma_books` 的写入。`books = state.books` 与后续多次对 `@Published` 属性的批量赋值会触发 SwiftUI 的观察者/订阅回调；在初始化/恢复期间这些回调可能导致重入或访问未就绪的资源，从而崩溃。请参阅文件中行 295-320 的赋值序列。

- `Sources/FeatureTTSReaderApp/Extensions.swift` — `OrderedSet` 越界风险
   - 行 97: `subscript(position: Int) -> Element { array[position] }`（无边界检查的直接索引）
   - 触发条件与证据：若上层调用使用过期/错误的索引值，会直接触发数组越界崩溃；证据为 subscript 未执行任何 range check（见行 97）。

- `Sources/FeatureTTSReaderApp/Models.swift` — `BookChapter` / `Book` 自定义 Codable 导致数据丢失
   - 行 31-36: `BookChapter.init(from:)` 将 `text = ""`（解码时丢弃原始 text）
   - 行 40-46: `BookChapter.encode(to:)` 未编码 `text` 字段
   - 行 73-78: `Book` 的 `init(from:)` 也将 `text = ""`（解码时丢弃）
   - 触发条件与证据：序列化/反序列化流程会丢失 `text`，在恢复状态后 `books` 中的章节文本为空，后续依赖文本的逻辑（如 `load_state_mainactor` 中对 `books[idx].text` 的比较/赋值）会出现不一致或导致意外路径。见文件行 31-78。

- `Sources/FeatureTTSReaderApp/BertSpeakerDetector.swift` — CoreML 并发访问风险
   - 行 7: `final class BertSpeakerDetector: @unchecked Sendable`（类声明）
   - 行 38: `guard let output = try? model.prediction(from: BertInput(...)) else { return nil }`（在 `embed(_:)` 中直接并发调用 model.prediction）
   - 触发条件与证据：将持有 `MLModel` 的类型标注为 `@unchecked Sendable` 并在并发上下文调用 `model.prediction`（行 38）会在无同步保护时导致数据竞争或崩溃，特别是在多任务/actor 调用此 detector 的场景中。


=== MainActor `load_state_mainactor` 的深入分析与临时仪表建议 ===

背景：
- 你提供的 marker 日志（`crash_marker`）和进一步的线索表明崩溃精确落在 `load_state_mainactor` 的执行内，而且发生在 `guard let state = decoded` 成功分支与随后的 `Self.writeCrashMarker("ls_ma_books")` 之间——也就是说崩溃早于写入 `ls_ma_books` marker 的那一步。

分析要点：
- 在 `MainActor.run { ... }` 内执行的批量 `@Published` 赋值（例如 `books = state.books`、`chapters`、`currentBook` 等）是高风险点：SwiftUI 的 `@Published` 在主线程上触发观察者回调，若在赋值时触发的观察者/订阅在同一执行路径中又发生 UI 更新或引发同步调用，可能造成重入或并发依赖，尤其在 app 初始化/恢复阶段多次触发 view lifecycle 时。
- 你的观察（`ls_ma_books` 未出现但 `load_state_mainactor` 有）强烈指向：赋值语句本身在执行时触发了崩溃（例如发布观察者在同步路径中触发了访问已释放资源或重复操作 continuation）。
- 另外 `Self.writeCrashMarker` 是 `nonisolated static`，在 `MainActor` 上调用通常是可行的，但若该函数内部有非线程安全的全局状态或文件 I/O 未 flush，也可能导致标记丢失；不过当前证据仍指向赋值触发的崩溃而非标记写入失败。

短期（可立即执行）的诊断与缓解步骤（建议写入代码以便验证）：
1. 在 `load_state_mainactor` 的 guard 成功分支中，在任何 `@Published` 赋值之前，立刻写入一个新的 marker（例如 `ls_ma_before_published`），并确保调用后立即 flush（以便在崩溃日志中能看到该 marker）。
2. 紧接着对每一组批量赋值加入单独 marker：
   - 在 `books = state.books` 前写 `ls_ma_before_books`，赋值后写 `ls_ma_after_books`。
   - 对 `chapters` / `currentBook` 等同理写前后 marker。
3. 将 `writeCrashMarker` 的实现临时增强为在写入后强制刷新磁盘（例如使用 `FileHandle` 的 `synchronizeFile()` 或 `fsync`），以提高 marker 在崩溃前被持久化的可能性。
4. 临时把这些批量 `@Published` 赋值改为分步（短期）或在赋值时用 `Task { await MainActor.run { ... } }` 分离观察者触发，观察是否能避免崩溃（这将验证是否为 `@Published` 同步回调引发的问题）。

长期修复建议（设计层面）：
- 避免在应用初始化的单个 MainActor.run 块中做大量同步的 `@Published` 批量赋值；改为分批、异步地设置状态，或在赋值前暂停/解除订阅可能会触发复杂路径的观察者。
- 为关键状态改变引入更明确的变更边界（例如通过 actor/队列封装状态写入，或在写入前短暂关闭监听器并在完成后重新注册），以消除在恢复期间的 re-entrancy 风险。

如果你同意，我可以：
- 在仓库中批量添加上述临时 markers（仅 instrumentation，不改业务逻辑），生成补丁供你运行并收集新的 `crash_marker` 来精确定位哪条赋值语句触发崩溃；或
- 仅生成补丁草案供你审阅，不应用到代码库。


