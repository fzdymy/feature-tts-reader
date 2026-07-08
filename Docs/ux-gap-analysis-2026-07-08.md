# ux-07-07 Blueprint vs. 实际代码差距分析

**生成日期:** 2026-07-08
**基准:** `Docs/ux-07-07.md` (蓝图) vs. `Sources/FeatureTTSReaderApp/` (代码)
**LiveContainer 约束:** AVAudioEngine + AVAudioSourceNode + 音频 tap → LiveContainer 侧载环境下导致 SIGSEGV/SIGABRT (见 AGENTS.md `62300cd`)

---

## 总体进度

| 状态 | 项数 | 说明 |
|------|------|------|
| ✅ 已完成 | 7 | VoiceEmbeddingRegistry, PlaybackAnchor, G2, G3(LRU), H5, AVAudioEngine 规避, 句级断句逻辑 |
| ⚠️ 部分完成 | 4 | DramaDirector(盲猜逻辑), F2(逐句=跳段落), F3(无并行预加载), F4(无Byte级进度) |
| ❌ 未完成 | 15 | BERT容错, MPRemoteCommandCenter, F1段落跳转, F5 tar.gz, F6并行合成, AsyncStream, VoiceCatalog清理, 句级UI高亮, RMS视觉反馈, HardReset, BookCharacter模型, SPM |

---

## 逐项分析

### A) AVAudioEngine Crossfade + Comfort Noise → 🛑 必须规避

**蓝图方案:** `AdvancedAudioPlaybackController` 使用 `AVAudioEngine` + `AVAudioPlayerNode` + `AVAudioSourceNode` + 双节点对数交叉淡化 + 舒适空气噪音 (-80dB)

**实际:** ✅ `AVAudioPlayer` 架构 (commit `62300cd`)

**原因:** AVAudioEngine 创建实时音频渲染线程。LiveContainer 侧载环境下音频 entitlements 缺失 → C++ 线程静默崩溃 (SIGSEGV/SIGABRT)。Xcode 真机调试可行但不可用于侧载。

**决策:** 蓝图中的 CAVAudioEngine 方案永久不可用于 LiveContainer。如需交叉淡化功能，需在非 LiveContainer 构建 (Xcode 真机) 中启用，且添加 `#if !targetEnvironment(simulator)` 守卫。

---

### B) VoiceEmbeddingRegistry (SHA256 缓存键)

**蓝图要求:** `actor VoiceEmbeddingRegistry`，通过对声纹二进制数据做 SHA256 生成唯一物理缓存键，根除 H3 串线问题

**实际状态:** ✅ 完全实现

| 组件 | 位置 | 状态 |
|------|------|------|
| `VoiceEmbeddingRegistry` actor | `VoiceEmbeddingRegistry.swift` | ✅ |
| `register()` / `registerAliases()` / `resolve()` / `embedding(for:) ` | 26-58 | ✅ |
| `cacheKey(for: text: emotionTag:)` w/ SHA256 | 60-65 | ✅ |
| 在 `playChapterStreaming()` 中集成 | Store.swift:1232-1246 | ✅ 注册所有声纹+别名 |
| 在 `synthesizeDialogueWithEmbeddings()` 中集成 | CosyVoiceService.swift:926-945 | ✅ registry 参数 + cacheKey |

**剩余差距:** `CosyVoiceService` 的 `cacheKey(text:embedding:)` (157-163) 是一个独立 SHA256 缓存, 不使用 Registry 。对话合成使用了 Registry, 单句合成未使用。

---

### C) DramaDirector (情感上下文平滑)

**✅ 基础类型已实现:** `DramaDirector` + `ContextWindow` + `SentenceContext` + `SentenceUnit`
**✅ 已接入合成管线:** Store.playChapterStreaming 两遍扫描, 第一遍构建 `allUpcomingSentenceContexts`, 第二遍在每组合成前调用 `director.contextualize()`
**❌ `CosyVoiceConfig` 死代码:** struct 存在但从未实例化或传递到合成器
**❌ 情感融合算法是占位符:** `blendEmotionTags`/`interpolateEmotionTag` 只是简单的比率选择而非真实 embedding 空间插值
**❌ 紧张关键词硬编码无英文回退:** 只有中文关键词, 英文小说不可用

**行动:** 要么增强融合逻辑为 embedding 空间插值, 要么移除占位符。接入 `CosyVoiceConfig`。添加英文/混合关键词。

---

### D) PlaybackAnchor (跨栈同步锚点)

**✅ 完全实现:**

| 组件 | 位置 |
|------|------|
| `PlaybackAnchor` struct | `PlaybackAnchor.swift` |
| `TTSQueueItem.anchor` 字段 | Models.swift:242 |
| `AdvancedAudioPlaybackController.currentAnchor` @Published | aaPC:8 |
| Anchor in `playNextSeamlessly()` | aaPC:54 |
| Store 监听 `currentAnchor` → `currentParagraphIndex` | Store.swift:183-191 |
| ReaderView 使用 `currentParagraphIndex` 自动滚动 | ReaderView.swift:211-221 |

**无差距。**

---

### E) F2 — 逐句跳过

**蓝图要求:** 每个句子独立合成为 WAV → 独立 `TTSQueueItem` → 逐句跳过 (`skipForward`/`skipToSentenceIndex`)

**实际状态:** ⚠️ 部分实现

| 组件 | 位置 | 状态 |
|------|------|------|
| `splitBlockIntoSentences()` | Store.swift:1150-1162 | ✅ |
| 句子解析 | playChapterStreaming:1293-1298 | ✅ |
| **连续同说话者句子合并为 1 组 → 1 个 WAV** | 1298-1326 | ❌ 每组对应一个 TTSQueueItem |
| `playNext()`/`skipForward()` 逐项跳过 | aaPC:91-93 | ✅ 跳转单位是组不是句 |

**差距本质:** 如果一个角色连续说 5 句话, 这 5 句被合并成 1 个 WAV, 跳过时 5 句一起跳过。要实现真正的逐句跳过, 每句必须独立合成独立 `TTSQueueItem`, 根据 `sentenceIndex` 跳转。

**行动项:** 移除同说话者分组。每句独立合成为独立 WAV + TTSQueueItem。添加 `skipToSentenceIndex()`。

---

### F) F3 — 多 Block 预加载队列

**蓝图要求:** 首个 block 合成后立即 `playQueue()`, 后续 block 在后台预合成, 通过 TaskGroup 并行提前加载

**实际状态:** ⚠️ 部分完成

| 组件 | 位置 | 状态 |
|------|------|------|
| `playQueue()` + `appendToQueue()` | aaPC:28-41 | ✅ |
| 首个 block 立即开播 | Store.swift:1434-1458 | ✅ `playQueue(firstBatch)` |
| 后续 block 追加 | 1456-1458 | ✅ `appendToQueue(batchItems)` |
| **并行预合成 (TaskGroup)** | — | ❌ 串行 for 循环, 一次一个 block |
| **前瞻性后台预获取** | — | ❌ block 只在轮到它时才合成 |

**差距:** "预加载" 当前只是 "合成完再入队"——队列用已有内容, 但播放时没有后台合成。蓝图要求 TaskGroup + AsyncSemaphore(maxConcurrent: 3)。

---

### G) F1 — fromParagraph 精确跳转

**蓝图要求:** 使用 `paragraphIndex` 从队列定位, `skipToSegment(targetIndex)` 精准跳转

**实际状态:** ❌ 未实现

- `fromParagraph` 参数存在但使用**文本匹配** (`paragraphs.firstIndex(where: { $0.contains(paraText) })`) → 有歧义, 脆弱
- 无 `jumpToParagraph(index:)` 方法
- 无 `skipToSegment(_:)` 方法 (AdvancedAudioPlaybackController 没有)

**行动项:** 添加 `skipToSegment(_:)`。实现 `Store.jumpToParagraph(index:)` 用 `paragraphIndex` 搜索队列。用索引-based 启动替换文本匹配。

---

### H) F4 — 流式下载进度

**实际状态:** ⚠️ 部分完成

当前使用 `task.progress.observe(\.fractionCompleted)` KVO, 提供平滑中间进度。蓝图要求 `URLSessionDownloadDelegate.didWriteData` 字节级精度。KVO 方案功能足够, 无需迁移。

---

### I) F5 — .tar.gz 文件导入

**蓝图要求:** UTType `.gzip` + `.data`, `startAccessingSecurityScopedResource()` 生命周期

**实际状态:** ❌ 未实现

- 当前文件导入器只接受 `.folder` 或 `.zip`
- 无 tar/gzip 解压代码 (只有 zip 解压)
- 安全作用域生命周期处理部分完成 (TTSView 行 404 但对 `.folder`)

**行动项:** 添加 UTType 支持 `.tar.gz`, 实现 tar 解压, 确保安全作用域生命周期。

---

### J) F6 — 并行合成

**实际状态:** ❌ 未实现

合成循环完全串行 (`for block in blocks`), 没有 `TaskGroup` + `AsyncSemaphore`。每个句子组等待前一个完成。

---

### K) G1 — VoiceCatalog / VoiceItem 清理

**实际状态:** ❌ 未实现

| 遗留物 | 位置 | 状态 |
|--------|------|------|
| `VoiceItem` struct | Models.swift:207-218 | ❌ Azure 风格字段 |
| `CharacterRecommendation.suggestedVoices` | Models.swift:288-293 | ❌ 引用 VoiceItem |
| `Store.voices: [VoiceItem]` | Store.swift:22 | ❌ 还发布着 |
| `Store.refreshVoices()` | Store.swift:986-988 | ❌ no-op 存根 |
| `defaultMaleVoiceID`/`defaultFemaleVoiceID` | Store.swift:140-141 | ❌ 存储但未使用 |

整个 Azure 语音系统已死代码, 全部应删除。

---

### L) G2 — CharacterEditorView Azure 控件移除

**✅ 已完成:** Azure 语速/音调/风格滑块已移除。当前显示声纹克隆状态 + 灵敏度 + 导入按钮。

---

### M) G3 — 磁盘缓存 LRU 驱逐

**✅ 已实现:** `CosyVoiceService.evictDiskLRU()` (196-224), 100 MB 配额, 按修改日期排序, 每次缓存存储后自动调用。缓存统计跟踪。

---

### N) MPRemoteCommandCenter / NowPlaying 集成

**❌ 已移除 (功能回归):**

`AdvancedAudioPlaybackController`:
- `updateNowPlaying()` → 空方法 `{}`
- 无 `MPRemoteCommandCenter` 设置
- 无 `MPNowPlayingInfoCenter` 更新
- 锁屏控制 / CarPlay 完全损坏

**蓝图 (旧 `Services.swift`)** 有完整实现: play/pause/stop/next/previous/seek/skipForward/skipBackward 命令 + 进度 + 专辑封面。

**行动项:** P0 — 从旧 `Services.swift` 蓝图代码重新实现 MPRemoteCommandCenter。恢复播放控制基本功能。

---

### O) ReaderView 句级高亮

**实际状态:** ❌ 未实现 (段落级只)

- `paragraphView()` → render 整个段落为一个 `Text` 块
- 段落级高亮: `paragraphIndex` 匹配 → 整段背景色
- 无句级拆分, 无句级颜色, 无句级点击跳转

**蓝图要求** 拆分为 `ForEach(sentences)` 每个 `Text` 单独着色, `.onTapGesture` 定点跳转。

---

### P) RMS 视觉反馈

**实际状态:** ❌ 未实现

`audioVolumeRMS` 在 controller 中发布, 但 **ReaderView 从未读取**。无音频电平指示器。

---

### Q) DramaStageRadarView

**实际状态:** ❌ 不存在

蓝图描述的 "声场雷达/角色声谱矩阵" 组件未实现。无活跃角色可视化。

---

### R) H5 — Book.text 缓存写回

**✅ 已解决:** `loadAllTextsFromFiles()` 将文本写回 `books[idx].text`。`loadStateAsync()` 正确写回。无差距。

---

### S) G4 — BERT 检测错误处理

**实际状态:** ❌ 未实现

`bertDetector.detectSpeaker() ` 调用在可选链中但**没有 `try-catch`**。如果 `detectSpeaker` 抛出, 向上传播导致崩溃。

**行动项:** 包装 BERT 调用为 `do-catch`, 记录错误并回退到仅正则检测。

---

### T) Hard Reset & Flush (immediateInterruptAndSeek)

**实际状态:** ❌ 未实现

无 `jumpToParagraph(index:)`。`stop()` 存在但无干净的中断-跳转-重建流程。

---

### U) AsyncStream 生产者-消费者管线

**实际状态:** ❌ 未实现

整个 `playChapterStreaming()` 是同步 for 循环 + `await` 每次合成。无 `AsyncStream<TTSQueueItem>` 管线。蓝图的优雅生产者-消费者模式 (后台 `Task.detached` 通过 `continuation.yield()`, 消费者实时入队) 不存在。

---

### V) BookCharacter 模型 with voiceEmbedding

**实际状态:** ❌ 未实现

代码库使用 `CharacterProfile`。蓝图中的 `BookCharacter` 有 `voiceEmbedding` 属性。当前 `CharacterProfile.voiceSampleEmbedding` 存储为 `Data?` (JSON 编码的 `[Float]`), 而不是字段化的 `voiceEmbedding: [Float]`。

---

## 优先级行动事项

### P0 — 必须立即修复

1. **N: MPRemoteCommandCenter** — 锁屏/CarPlay 播放控制完全损坏。从旧 `Services.swift` 蓝图代码恢复实现。**注意:** 在 LiveContainer 下, `MPRemoteCommandCenter` 可能也不完全工作, 需要在非 LiveContainer 中测试。
2. **S: G4 BERT 错误处理** — `detectSpeaker()` 无错误处理会崩溃。

### P1 — 高影响

3. **E: F2 逐句跳过** — 移除同说话者分组, 每句独立合成。
4. **F: F3 并行预加载** — 结合 F6 用 TaskGroup + semaphore 实现。
5. **G: F1 段落索引跳转** — 用 `paragraphIndex` 搜索队列替代文本匹配。
6. **J: F6 并行合成** — 与 F3 合并, 一次实现。

### P2 — 架构债务

7. **U: AsyncStream 管线** — 生产者-消费者流式模式。
8. **K: G1 VoiceCatalog 清理** — 移除所有 Azure 死代码。
9. **O: 句级高亮** — ReaderView 逐句着色。
10. **T: Hard Reset & Flush** — 干净中断-跳转-流。

### P3 — 打磨

11. **P: RMS 视觉反馈** — 音频电平指示器。
12. **Q: DramaStageRadarView** — 角色可视化组件。
13. **C: DramaDirector 增强** — 超越占位符逻辑。
14. **B: 注册表缓存统一** — 单一缓存键策略。
15. **I: F5 tar.gz 导入** — gzip 解压支持。
16. **V: BookCharacter 模型** — 添加类型化的 `voiceEmbedding` 字段。