# FeatureTTSReader — 遗留问题修复 Prompt (v3)

## 当前项目状态 (2026-07-09)

### 修复执行结果 (2026-07-09)

**更新状态:**

| # | 优先级 | 状态 | 说明 |
|---|--------|------|------|
| R1 | P0 编译错误 | ✅ 已修复 | `cosySegments`/`embedPayload` 死代码删除 (Store.swift) |
| R2 | P1 死锁 | ✅ 已修复 | `withCheckedContinuation` 添加 10s 超时兜底 |
| R3 | P1 竞态 | ✅ 已修复 | `cancelPlaybackTaskAndWait` 取本地快照再 cancel/await；`stopPlayback` 同步 |
| R4 | P1 内存 | ✅ 已修复 | `playbackHistory` 上限 200，超过移除最旧 |
| R5 | P1 功能 | ✅ 已修复 | `paragraphIndex` 精确匹配优先，去标点容错，子串兜底 |
| R6 | P1 UX | ✅ 已修复 | 单击 = 仅选中句子（不播放），双击 = 选中 + 从该句开始播放 |
| R7 | P2 清理 | ✅ 已修复 | 删除 `voiceSampleEmbedding`（9处引用全清）；保留 `voiceSampleURL`（CharacterEditorView 用户样本功能仍用） |
| R8 | P2 代码 | ✅ 已修复 | 新增 `isSentenceReading(pi:si:isCurrentChapter:)` 辅助函数；`sentenceView` 改用此函数 |
| R9 | P2 重复 | ✅ 已处理 | 保留内联实现（有进度UI+Phase4 titleSuffix合并+动态minFreq+性别fallback等增强，直接替换会丢失功能）；修正 `CharacterScanner.swift` 第4行误导性注释 |
| R10 | P3 记录 | ℹ️ 知悉 | `TTSQueueItem.id` 不持久化（按设计，queue item 是 ephemeral），无需修改 |

**新增已知问题:**

| # | 优先级 | 说明 |
|---|--------|------|
| R11 | P3 | `Store.enableDoubleTapToSpeak` 设置仍存 (Store.swift:113, SettingsView.swift:128) 但 ReaderView 双击手势现在恒定执行播放，未真正读取此开关。若想恢复"用户可关闭双击播放"功能，可在双击手势外加 `if store.enableDoubleTapToSpeak`，否则可删除该 setting |
| R12 | P2 验证 | `Store.swift:1340` `profile?.voice.isEmpty == false ? profile?.voice : nil` 解包后又传 nil，等价于 `profile?.voice?.isEmpty == false ? profile?.voice : nil`；但 `voice` 是 `String` 不可为 nil，`profile?.voice` 的 optional chain 之后类型为 `String?`，写法可读性差但正确 |

**下一步行动（按优先级）:**
1. **触发 CI 验证编译** — 推送当前 commit 到 `origin/ci-check/asyncstream-refactor` 分支，检查 build 是否绿
2. **R7 后续（可选）** — 若确认用户样本功能不再需要，可进一步删除 `voiceSampleURL` 及 CharacterEditorView 的样本 UI（当前保留）

---

## 原始 Prompt 内容（修复要求，供回溯参考）

### 已完成的核心迁移:
**
- ✅ CosyVoiceService.swift 已删除
- ✅ VoiceEmbeddingRegistry.swift 已删除
- ✅ BertSpeakerDetector.swift 已删除
- ✅ EdgeTTSService.swift 已实现（270 行，完整 synthesize/SSML/healthCheck/多服务器）
- ✅ Store.swift 合成管线已改为 EdgeTTSService，零 CosyVoice 引用
- ✅ TTSView.swift 已重写为 Edge TTS 服务器配置 UI
- ✅ 最近 commit `8350660` CI 编译绿色通过

## 剩余需修复问题（按优先级）

### P0 — 编译错误（阻塞 CI）

#### #R1: `embedPayload` 未定义变量

**文件:** `Store.swift:1325-1331`
**问题:** `cosySegments` 和 `embedPayload.dict`/`embedPayload.samples` 是 CosyVoice 时代残留，`embedPayload` 从未定义。当前合成已使用 `EdgeTTSService.shared.synthesize()`，这些变量不再需要。

**旧代码 (行 1325-1331):**
```swift
                            let cosySegments: [(String, String, String?)] = [(canonical, sentence, refined.emotionTag)]

                            group.addTask {
                                let emb = embedPayload.dict
                                let samples = embedPayload.samples
                                await semaphore.wait()
                                defer { semaphore.signal() }
```

**新代码:**
```swift
                            group.addTask {
                                await semaphore.wait()
                                defer { semaphore.signal() }
```

---

### P1 — 运行时风险

#### #R2: `withCheckedContinuation` 无超时 → 播放完成后可能死锁

**文件:** `Store.swift:1415-1423`
**问题:** 如果播放器 `isPlaying` 永远不会变 false（如音频文件损坏），continuation 永不 resume → `playChapterStreaming` 永久挂起 → 用户无法第二次播放。

**旧代码 (行 1415-1423):**
```swift
        // Wait for playback completion
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if !audioController.isPlaying { cont.resume(); return }
            let c = audioController.$isPlaying
                .dropFirst().filter { !$0 }.first()
                .sink { _ in cont.resume() }
            playbackContinuationCancellable = c
        }
        playbackContinuationCancellable = nil
```

**新代码:**
```swift
        // Wait for playback completion with timeout
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if !audioController.isPlaying { cont.resume(); return }
            let c = audioController.$isPlaying
                .dropFirst().filter { !$0 }.first()
                .sink { _ in cont.resume() }
            playbackContinuationCancellable = c
            // 超时兜底: 10秒后无论是否播完都 resume
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                if self?.playbackContinuationCancellable != nil {
                    cont.resume()
                    self?.playbackContinuationCancellable = nil
                }
            }
        }
        playbackContinuationCancellable = nil
```

---

#### #R3: `cancelPlaybackTaskAndWait` vs `stopPlayback` 竞态

**文件:** `Store.swift:1095-1103`
**问题:** `cancelPlaybackTaskAndWait()` (async) 和 `stopPlayback()` (非 async) 都可以修改 `playbackTask`。当一个在 `try? await playbackTask?.value` 中间时，另一个可能置 `playbackTask = nil`，导致 await 的是 nil（立即返回），但任务实际未完成。

**旧代码 (行 1095-1103):**
```swift
    private func cancelPlaybackTaskAndWait() async {
        playbackTask?.cancel()
        try? await playbackTask?.value
        playbackTask = nil
    }

    func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
```

**新代码:**
```swift
    private func cancelPlaybackTaskAndWait() async {
        let task = playbackTask
        playbackTask = nil  // 先清空，防止并发赋值
        task?.cancel()
        _ = try? await task?.value
    }

    func stopPlayback() {
        let task = playbackTask
        playbackTask = nil
        task?.cancel()
```

---

### P1 — 功能缺陷

#### #R4: `playbackHistory` 无上限 → 内存泄漏

**文件:** `AdvancedAudioPlaybackController.swift:108`
**问题:** 每次播放完成都 append，从未检查大小。10000 句播放后数组持有 10000 个 `TTSQueueItem`（含 audioURL）。

**旧代码 (行 108):**
```swift
            playbackHistory.append(currentItem)
```

**新代码:**
```swift
            playbackHistory.append(currentItem)
            if playbackHistory.count > 200 {
                playbackHistory.removeFirst(playbackHistory.count - 200)
            }
```

---

#### #R5: `paragraphIndex(for:in:)` 文本匹配脆弱

**文件:** `Store.swift:1863-1868`
**问题:** 使用 `$0.contains(trimmed) || trimmed.contains($0)` 匹配段落。两段含相同子串时返回错误段落；空 trimmed 返回 nil 导致从开头播放。

**旧代码 (行 1863-1868):**
```swift
    private func paragraphIndex(for paragraphText: String, in chapterText: String) -> Int? {
        let paragraphs = chapterText.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let trimmed = paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return paragraphs.firstIndex(where: { $0.contains(trimmed) || trimmed.contains($0) })
    }
```

**新代码:**
```swift
    private func paragraphIndex(for paragraphText: String, in chapterText: String) -> Int? {
        let paragraphs = chapterText.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let trimmed = paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 精确匹配整段内容，避免子串歧义
        if let exact = paragraphs.firstIndex(where: { $0 == trimmed }) { return exact }
        // 容错: 去掉末尾句号再匹配 (用户选择的文本可能是含标点或不含标点的版本)
        let withoutPeriod = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "。！？!?."))
        if withoutPeriod != trimmed {
            return paragraphs.firstIndex(where: { $0 == withoutPeriod || $0.hasPrefix(withoutPeriod) })
        }
        // 最后容错: 子串包含匹配（保留 Original 兼容性）
        return paragraphs.firstIndex(where: { $0.contains(trimmed) })
    }
```

---

#### #R6: ReaderView 双击/单击冲突

**文件:** `ReaderView.swift:1460-1473`
**问题:** 同一个 Text 上同时有 `.onTapGesture`（单击选中）和 `.onTapGesture(count: 2)`（双击播放）。SwiftUI 在双击发生时可能先触发单击选中→高亮→滚动，再触发双击播放→再滚动，体验抖动。

**期望行为（已实施）:** 单击 = 仅选中句子（不播放），双击 = 选中 + 从该句开始播放。保留两个手势，但双击只执行 `selectSentence + immediateInterruptAndSeek` 一次；单击只执行 `selectSentence`。

**保留原代码 (行 1460-1473)** 保持不变 — 已符合期望行为。

**备注:** 若 SwiftUI 仍然先触发单击再触发双击导致 scroll 抖动，可考虑改用 UIKit `UITapGestureRecognizer`（设置 `tap.require(toFail: doubleTap)`），但当前 SwiftUI 内置机制优先采用 `count: 2`，双击事件优先处理，应可正常工作。

---

### P2 — 代码重复 / 清理

#### #R7: `CharacterProfile` 遗留字段

**文件:** `Models.swift:105-106`
**问题:** `voiceSampleURL` 和 `voiceSampleEmbedding` 是 CosyVoice 声纹克隆遗留。`voiceSampleEmbedding` 已标注 "当前未使用"。Edge TTS 不需要这些字段。

**旧代码 (行 104-107):**
```swift
    var voiceSampleURL: URL?  // 角色参考音频（可选）
    var voiceSampleEmbedding: Data?  // 兼容字段，当前未使用
```

**新代码:**
```swift
    // voiceSampleURL/voiceSampleEmbedding 已废弃（CosyVoice 时代字段）
```

> 注意: 如果这些字段在后面有被引用（CharacterEditorView、Store 存档等），需要同步清理所有引用。

---

#### #R8: `isSentenceReading` 辅助函数缺失

**文件:** `ReaderView.swift`
**问题:** `isParagraphReading` 存在（行 1478），但句子级高亮在内联使用 `store.currentParagraphIndex == pi && store.currentSentenceIndex == si`，没有统一的辅助函数。

**在 `isParagraphReading` 附近添加:**
```swift
    private func isSentenceReading(pi: Int, si: Int, isCurrentChapter: Bool) -> Bool {
        guard isCurrentChapter else { return false }
        return store.currentParagraphIndex == pi && store.currentSentenceIndex == si
    }
```

**更新行 ~1432 的高亮:**
```swift
// 旧:
let isHighlighted = isCurrentChapter && store.currentParagraphIndex == pi && store.currentSentenceIndex == si
// 新:
let isHighlighted = isSentenceReading(pi: pi, si: si, isCurrentChapter: isCurrentChapter)
```

---

#### #R9: `CharacterAssignmentView` 内联扫描管线

**文件:** `CharacterAssignmentView.swift:241-386`
**问题:** `startScan()` 重新实现了 CharacterScanner 的三阶段管线（extractCandidates → countCharacterFrequencies → estimateAttributes），共 ~145 行重复代码。两份实现可能分化出不同的行为。

**建议的简化:**
```swift
    private func startScan() async {
        guard let bookText = store.bookText else { return }
        let config = CharacterScanner.Config(maxResults: 12, useNLValidation: true, includeGraph: false)
        let result = await CharacterScanner.scan(text: bookText, config: config, voices: [], defaultSensitivity: 50, bookID: store.currentBookID)
        var merged = result.characters
        for existing in store.characters {
            if !merged.contains(where: { $0.name == existing.name }) {
                merged.append(existing)
            }
        }
        await MainActor.run { store.characters = merged; isLoading = false }
    }
```

删除 `CharacterAssignmentView.swift` 行 241-386 中的内联实现，替换为上述调用。

---

### P3 — 低优先级

#### #R10: `TTSQueueItem` CodingKeys 不含 `id`

**文件:** `Models.swift:244-246`
**问题:** `id` 不在 CodingKeys 中。encode→decode 后每个 item 获得新 UUID。如果将来需要序列化队列状态（如恢复播放），此字段需要持久化。
**当前不阻碍编译/功能**（queue item 是 ephemeral 的），记录为知晓。

---

## 实现要求

1. **每处修改提供 oldString/newString** — 精确匹配文件内容，包括空格和换行。
2. **基于最新 commit** — 当前 HEAD = `8350660`。
3. **先修 P0 (R1)**，再修 P1 (R2-R6)，再修 P2 (R7-R9)。
4. **每修完一批推 CI 验证** — `git add -A && git commit -m "fix: ..." && git push`。
5. **不要重构** — 只做精确替换。
6. **不要引入新文件** — 所有修改都在现有文件中。
