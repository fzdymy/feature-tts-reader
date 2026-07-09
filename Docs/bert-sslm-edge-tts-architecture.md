# FeatureTTSReader — 性能优化 + 流式合成 + 4层架构设计

## 核心设计哲学

1. **所有操作必须流畅** — 点击 < 50ms，滚动 60fps，高亮切换不丢帧
2. **播放必须立即开始** — 首句 < 300ms 出声，不等待预处理/BERT/批处理
3. **内容必须流式发送** — 不等待全量分析，不等待完整 HTTP 响应，边合成边播
4. **朗读页必须精简** — 删除所有死代码/冗余模块，配置归 SettingsView

---

## 现有问题诊断

### 🔴 P0.1: ReaderView 所有动作卡顿 (已分析，见下 S1-S12)

### 🔴 P0.2: TTSView 模块冗余、功能抵消

TTSView.swift (224 行) 有 5 个 section，大部分是 CosyVoice 遗留死代码或冗余功能：

| Section | 行 | 问题 | 处理 |
|---------|----|------|------|
| `engineSection` | 40-56 | Health 状态由 `timer` 每秒轮询刷新，浪费 CPU | 合并到 `downloadSection`，事件驱动 |
| `downloadSection` | 60-101 | 服务器配置（有用），但 TextEditor + save/copy + explanation 太冗长 | 保留精简 |
| `testSection` | 106-137 | 调用 `testTTSSynthesize` 测试合成，再调用 `audioController.playFilesAndWait` 播放。与主播放管线完全重复——用户在 ReaderView 中选句就能听，不需要独立测试入口。且 `playFilesAndWait` 阻塞主线程 | **删除** |
| `samplesSection` | 184-223 | `voiceSamples` 从 `Models/default_samples/` 读 .wav 文件。这是 CosyVoice 声纹样本（indextts2_duration 相关），Edge TTS 时代完全无用。**且这些文件可能不存在于 release bundle** | **删除** |
| `infoSection` | 141-154 | 静态说明文字 + `store.statusMessage` 显示。状态消息在 ReaderView 已经有 | **删除** |

**功能抵消的具体表现：**
- `testSection` 播放测试音频时，如果主播放管线正在运行，`playFilesAndWait` 打断当前播放
- `timer` 每 1 秒轮询 `healthCheck()`，同时 `refreshStatus` 又写 `healthMessage` 到 UI——但用户从不盯着 TTSView 看
- `samplesSection` 播放 CosyVoice 样本音频，对 Edge TTS 没有任何意义

### 🔴 P0.3: 合成管线 2 遍扫描 + 串行 HTTP，全量等待

`playChapterStreaming()` (Store.swift:1281-1504) 有 3 个结构性性能问题：

**问题 A: 2 遍扫描（行 1312-1332 + 行 1343-1441）**
```
第 1 遍 (行 1312-1332): 遍历所有 blocks → 所有 sentences → parseDialogueSegments
                → 填充 allUpcomingSentenceContexts（仅用于 DramaDirector 前瞻）
第 2 遍 (行 1343-1441): 再次遍历所有 blocks → 所有 sentences → parseDialogueSegments
                → DramaDirector → EdgeTTSService.synthesize
```
浪费：第 1 遍扫描了全部文本才开始合成，对 500 句小说 = 500 次正则解析白做一次。
`allUpcomingSentenceContexts` 仅用于 `DramaDirector.ContextWindow.upcomingSentences`，但前瞻窗口只需要 5 句——不需要扫完全文。

**问题 B: HTTP 串行阻塞（行 1400）**
```
每个句子: HTTP GET /tts?t={SSML} → 等待完整 MP3 响应（~200ms/句）
          → 写入临时文件 → yield to stream
```
3 并发 semaphore 但每个 HTTP 请求仍然是同步等待完整 body。
对 300 句小说 = 300 × 200ms = 60s 纯网络等待。

**问题 C: WAV 文件 I/O（行 1416-1417）**
每个句子写一个临时文件到磁盘，播放完再删除（行 1496）。
300 句 = 300 次 write + 300 次 read（AVAudioPlayer 读文件）+ 300 次 delete。
文件 I/O 约 5-10ms/次，合计 1.5-3s 纯磁盘开销。

**问题 D: consumer 等待首句入队才开始播放（行 1463）**
首句合成开始 → 等待 HTTP 响应 → 写文件 → yield → consumer 收到 → playQueue
从点击到出声 = 首句 HTTP 延迟（~200ms）+ 文件写（~10ms）= ~210ms。
但如果有更快的方案可以降到 ~50ms（见下流式方案）。

---

## 修复方案

### 🔴 S13: TTSView 精简为纯配置页 【P0】

替换 224 行复杂 List 为 ~50 行简洁配置卡：

```swift
struct TTSView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var serverListText = ""
    @State private var apiKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("服务地址（每行一个）", text: $serverListText, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                    TextField("API Key（可选）", text: $apiKey)
                        .autocorrectionDisabled()
                    Button("保存并测试连接") { saveAndTest() }
                } header: {
                    Label("Edge TTS 服务器", systemImage: "server.rack")
                } footer: {
                    Text("默认: \(EdgeTTSService.defaultServerURL)")
                        .font(.caption)
                }

                Section {
                    StatusRow(label: "连接状态", value: connectionStatus)
                    StatusRow(label: "朗读模式", value: "流式实时合成")
                } header: {
                    Label("状态", systemImage: "info.circle")
                }
            }
            .navigationTitle("语音设置")
            .onAppear {
                Task {
                    serverListText = await EdgeTTSService.shared.serverListText
                    apiKey = await EdgeTTSService.shared.apiKey
                }
            }
        }
    }

    private var connectionStatus: String {
        // 不轮询，只显示上次测试结果
        store.edgeTTSLastHealth
    }
}

struct StatusRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).foregroundColor(.primary)
        }
    }
}
```

**删除内容：**
- `samplesSection` — CosyVoice 死代码
- `testSection` — 与主播放管线重复，删除
- `infoSection` — 纯文字说明，无功能价值
- `timer.publish(every: 1)` — 每秒轮询浪费 CPU
- `refreshStatus()` — 改为保存时事件驱动检查

**合并到 SettingsView：**
- 服务器配置 UI 从独立 TTSView 移到 SettingsView 的 "语音" 分组

### 🔴 S14: 合成管线改为单遍流式 + 预取管道 【P0】

**核心变更: 删除第 1 遍扫描，改为惰性前瞻**

```swift
func playChapterStreaming(chapter: BookChapter, ...) async throws {
    // === 不再有第 1 遍全量扫描 ===
    // 删除 lines 1312-1332: 整个 allUpcomingSentenceContexts 构建

    // === 改为: 运行时惰性构建 ContextWindow ===
    // 使用滑动窗口：只需要缓存当前 + 后续 5 句的上下文
    var upcomingContextBuffer: [DramaDirector.SentenceContext] = []

    // ... AsyncStream producer ...

    for sentence in sentences {
        // 惰性填充前瞻缓冲区（最多 5 句）
        if upcomingContextBuffer.count < 5 {
            let nextCtx = buildSentenceContext(sentence, characters, ...)
            upcomingContextBuffer.append(nextCtx)
        }

        let contextWindow = DramaDirector.ContextWindow(
            previousDialogue: previousDialogueContext,
            upcomingSentences: Array(upcomingContextBuffer.prefix(5)),
            // ...
        )
        let refined = director.contextualize(unit, context: contextWindow)

        // 消费后移除
        if !upcomingContextBuffer.isEmpty { upcomingContextBuffer.removeFirst() }
    }
}
```

**收益：** 消除全量扫描延迟。500 句小说节省 ~500ms 预处理时间。首句从 ~210ms 降到 ~50ms。

### 🔴 S15: HTTP 预取管道 —— 提前发请求，不等待响应 【P0】

**核心变更: 不在 TaskGroup 内等 HTTP 完成，改用预取 buffer**

```swift
// 当前: TaskGroup 内 await EdgeTTSService.shared.synthesize → 等待响应
// 改为: 用 async let 或 Task 做预取，存 buffer

actor AudioPrefecther {
    private var prefetchBuffer: [Int: Data] = [:]
    private var inflightRequests: Set<Int> = []
    private let maxPrefetch = 5

    func prefetch(index: Int, text: String, voice: String?, rate: Double, pitch: Double, emotionTag: String?) {
        guard !inflightRequests.contains(index), prefetchBuffer[index] == nil else { return }
        inflightRequests.insert(index)
        Task.detached(priority: .utility) { [weak self] in
            let data = try? await EdgeTTSService.shared.synthesize(
                text: text, voice: voice, rate: rate, pitch: pitch, emotionTag: emotionTag
            )
            await self?.storeResult(index, data)
        }
    }

    func waitFor(index: Int) async -> Data? {
        // 如果已预取完成，立即返回
        if let data = prefetchBuffer[index] { return data }
        // 否则等待（IO 绑定的等待，不阻塞 UI）
        return await withCheckedContinuation { cont in
            pendingWaits[index] = cont
        }
    }

    private func storeResult(_ index: Int, _ data: Data?) {
        inflightRequests.remove(index)
        if let data = data {
            prefetchBuffer[index] = data
            pendingWaits[index]?.resume(returning: data)
            pendingWaits[index] = nil
        }
    }
}
```

**在 playChapterStreaming 中的集成：**

```swift
let prefetcher = AudioPrefecther()

// 预取前 5 句（在首句合成前就发出）
for i in 0..<min(5, totalSentences) {
    prefetcher.prefetch(index: i, text: sentences[i], ...)
}

for (index, sentence) in sentences.enumerated() {
    // 从预取器获取（可能是缓存命中，或等待网络）
    let audioData = try await prefetcher.waitFor(index: index)

    // 预取后续句子（滑窗）
    let nextIndex = index + maxPrefetch
    if nextIndex < totalSentences {
        prefetcher.prefetch(index: nextIndex, text: sentences[nextIndex], ...)
    }

    // 写入文件 + yield
    // ...
}
```

**收益：** HTTP 请求重叠。首句立即发出，第 2 句在第 1 句播放期间后台下载。300 句小说的总网络等待从 60s 降到 ~20s（5 并发滑窗）。

### 🟡 S16: 消除 WAV 文件 I/O，改用内存 Data 【P1】

`AdvancedAudioPlaybackController` 当前从 `URL` 播放音频。改为直接接受 `Data`：

```swift
// 当前:
let audioURL = audioDir.appendingPathComponent("blk-\(blockIdx)-s-\(sIdx)-\(UUID().uuidString).\(ext)")
try? audioData.write(to: audioURL, options: .atomic)  // 磁盘写
let item = TTSQueueItem(..., audioURL: audioURL, ...)

// 播放时: AVAudioPlayer(contentsOf: audioURL)  // 磁盘读

// 改为:
// TTSQueueItem 新增 audioData: Data? 字段（可选，不与 audioURL 共存）
let item = TTSQueueItem(..., audioData: audioData, audioURL: nil)

// AdvancedAudioPlaybackController:
// 如果 audioData 不为 nil，用 AVAudioPlayer(data: audioData) 直接播
```

**收益：** 300 句 × 2 次 I/O（写 + 读）= 600 次文件操作，省掉 600 次。约节省 3-6s。
同时省掉播放结束后的 cleanup 循环（行 1495-1497）。

### 🟡 S17: 优先合流 —— 多个句子合并成一个 HTTP 请求 【P1】

如果 Edge TTS 服务器支持多句 SSML（将多个 `<voice>` 标签放在一个 `<speak>` 里），则可以将同一说话者的连续句子批量发送：

```swift
// 检测连续相同说话者的句子，合并为一次请求
var batch: [(text: String, emotion: String?)] = []
for sentence in sentences {
    if batch.isEmpty || (speaker == lastSpeaker && batch.count < 3) {
        batch.append((sentence, emotionTag))
    } else {
        // 发送批次
        let ssml = buildMultiSentenceSSML(batch, voice: voice)
        let audioData = try await EdgeTTSService.shared.synthesize(ssml: ssml)
        batch = [(sentence, emotionTag)]  // 新批次开始
    }
}
```

**收益：** 减少 HTTP 往返次数。同说话者连续 3 句合并 = 减少 66% HTTP 请求。300 句 → ~100 次请求，节省 ~40s。

### 🟡 S18: 播放器支持内存 Data 而非仅 URL 【P1】

```swift
// AdvancedAudioPlaybackController.swift
// 新增: playData 方法

func playData(_ data: Data, ...) {
    // 使用 AVAudioPlayer(data: data) 直接从内存播
    do {
        let player = try AVAudioPlayer(data: data)
        // ...
    } catch {
        // fallback: 写临时文件
    }
}
```

---

## 完整实现顺序

### Phase 0 (P0, 立即做): 所有零延迟修复

| Step | 文件 | 改动 | 收益 |
|------|------|------|------|
| S5 | ReaderView | 删除 scaleEffect + overlay + animation；保留双击手势（单击无动作） | **双击响应 300ms→20ms** |
| S1 | ReaderView | @Published→@State 隔离 | **消除全树重算** |
| S3 | ReaderView | ChapterContentView Equatable | **非播放章节永不重算** |
| S4 | ReaderView | 段落断句缓存 | **滚动不再正则解析** |
| S2 | ReaderView | ZStack 拆 3 EquatableView | **操作不触发全量** |
| S13 | TTSView | **精简为纯配置页（50 行）** | **删除冗余、停止 1s 轮询** |

### Phase 1 (P0, 播放延迟): 流式合成管线

| Step | 文件 | 改动 | 收益 |
|------|------|------|------|
| S14 | Store.swift | **删除第 1 遍扫描，惰性前瞻** | **首句延迟 210ms→50ms** |
| S15 | Store.swift | **AudioPrefetcher 预取管道** | **300 句 60s→20s 网络等待** |
| S16 | Store+Playback | 内存 Data 代替文件 I/O | **省 600 次文件操作，~3-6s** |
| S18 | AdvanceAudio | `playData(_:)` 方法 | **支持内存播放** |
| S17 | Store.swift | 同说话者批量合流 | **300 句→100 请求，省 ~40s** |

### Phase 2 (P1): BERT CoreML 流式推理 (与 Phase 1 并行)

| Step | 文件 | 改动 | 收益 |
|------|------|------|------|
| B1 | BERTCoreMLEngine | 模型加载 + tokenizer | 256-dim embedding |
| B2 | BERTStreamPipeline | Stream actor + background queue | BERT 不阻塞 UI |
| B3 | Store.swift | fuseSpeakerDecision + 流式集成 | 渐进升级 speaker 精度 |

### Phase 3 (P2): SSLM 音色匹配

| Step | 文件 | 改动 | 收益 |
|------|------|------|------|
| M1 | voice_embeddings.json | 预计算音色嵌入库 | SSLM 数据基础 |
| M2 | SSLMVoiceMatcher | 余弦相似度 + 人设一致性 | 角色→音色自动匹配 |

### Phase 4 (P3): 情绪→韵律 + 打磨

| Step | 文件 | 改动 |
|------|------|------|
| E1 | EdgeTTSService | emotionProsodyMap 10+ 情绪扩展 |
| P1 | 全局 | BERT 状态 UI、热降级、统计 |

---

## 性能目标汇总

| 操作 | 当前 | Phase 0 | Phase 1 | 手段 |
|------|------|---------|---------|------|
| 双击句子 → 播放 | ~500ms | ~20ms | ~20ms | S5: 删 scaleEffect/overlay/animation |
| 滚动首次打开 | ~5s | <50ms | <50ms | S1+S3+S4 |
| 页面切换 | ~2s | <100ms | <100ms | S2+S13 |
| 首句出声 | ~210ms | ~210ms | **~50ms** | S14+S15 |
| 300 句总耗时 | ~90s | ~90s | **~25s** | S15+S16+S17 |
| TTSView 加载 | ~500ms | ~50ms | ~50ms | S13: 删 4 section |

---

## Bug 修复记录 (2026-07-09)

| # | Bug | 根因 | 修复 | 文件 |
|---|-----|------|------|------|
| B1 | TTS 服务器 URL 与 API Key 未配对 | TTSView 用独立 TextField 存 `apiKey`，`EdgeTTSService.apiKey` setter 覆盖所有服务器密钥 | TTSView 改为逐服务器 `{url, apiKey}` 列表；`setServers` 保持 per-server apiKey；全局 `apiKey` setter 不再覆盖 | `TTSView.swift`, `EdgeTTSService.swift` |
| B2 | 书籍二次打开丢失文本 | `loadStateAsync()` 中 `loadedTexts` 只加载 `state.books`（JSON 状态文件）的文本；从 Core Data persistence 合并的书籍不加载文件 | 新增 `for i in books.indices where books[i].text.isEmpty` 循环加载缺失文本；`bookText` 空时也从文件加载 | `Store.swift` |
| B3 | 区域单击手势消失 | S5 删除 triple-tap gesture 时未替换为 zone-based single-tap | 增加 `SpatialTapGesture` 在 ZStack：上 1/4 翻页下滚（保留末 2 行），中 1/2 沉浸切换，下 1/4 翻页上滚；250ms 延迟避免双击冲突 | `ReaderView.swift` |
| B4 | 语音设置测试功能消失 | S13 精简 TTSView 时删除 `testSection` | 恢复 testSection：自定义文本输入 + 试听按钮 + 结果显示 | `TTSView.swift` |
