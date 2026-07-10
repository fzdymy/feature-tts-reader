# FeatureTTSReader — On-Device Multi-Role TTS

## 关键变更记录 (2026-07-08)

### 🛑 P0 Crash: AVAudioEngine render thread 导致 LiveContainer 启动崩溃

**根因**: AdvancedAudioPlaybackController 使用 AVAudioEngine + AVAudioPlayerNode + AVAudioSourceNode 时，`engine.start()` 创建了一个 real-time audio render thread。在 LiveContainer (sideload) 环境下，音频 entitlements 缺失导致该 C++ 线程静默崩溃 (SIGSEGV/SIGABRT)，表现为 app 启动闪退。

**诊断过程**:
1. Binsearch 确认 `9713f0c` (完全禁用引擎) 不 crash → 音频引擎是唯一原因
2. 将 engine start 移到 `Task.detached(background)` 仍 crash → 不是主线程阻塞问题
3. 用细粒度 `writeCrashMarker` 追踪发现所有启动步骤 (init → body → onAppear → setup → loadState) 都完成，但完成后立即崩溃 → 音频后台线程异步崩溃
4. 移除 RMS tap、split engine setup/create → 仍 crash

**修复**: 将 AdvancedAudioPlaybackController 从 AVAudioEngine 架构**完全重写**为 AVAudioPlayer 架构:
- 删除 `AVAudioEngine`、`AVAudioPlayerNode`、`AVAudioSourceNode`、`AVAudioMixerNode`、crossfade 逻辑
- 使用 `AVAudioPlayer` (系统级播放器，无需自定义音频渲染线程)
- `ensureEngineSetup()` / `ensureEngineStarted()` 留为空方法 (兼容外部调用)
- RMS 音量使用 `AVAudioPlayer.averagePower(forChannel:)` + Timer 轮询 (非 audio render thread)
- 队列连续播放由 `AVAudioPlayerDelegate.audioPlayerDidFinishPlaying` 驱动
- `configureAudioSession()` 移至每次 `playNextSeamlessly()`

**提交**: `62300cd` (重写), `278c21a`/`df65942` (编译修复)

**后续注意**: 未来若需 AVAudioEngine 的 crossfade 功能，需先在非 LiveContainer 环境 (Xcode 真机调试) 测试通过，确认音频 entitlements 齐全后再引入。

### 其他并发修复
- RMS tap 中的 `Task { @MainActor }` 改为 `DispatchQueue.main.async` — 避免从 audio render thread 创建 Swift Task 导致的底层并发崩溃 (`1ea59a8`)
- `loadStateAsync` 从 `Store.init` 的 `Task {}` 移出，改为 `onAppear` 的 background task 中调用 — 避免 init 期间 `@Published` sink 触发 SwiftUI body 重算导致竞态 (`159d6e1`)
- `writeCrashMarker` 文件并发写入已移除 — 之前 `nonisolated static` 从多个线程写入同一文件可能导致文件系统异常 (`21f9f30`)

---

# FeatureTTSReader — On-Device Multi-Role TTS

## 现状 (2026-07)

- iOS 18+ / Swift 5.9 / SwiftUI / Xcode 26.3+
- 角色检测: BERT embedding + 余弦相似度 (77% 准确率)
- TTS: CosyVoice 3 DialogueSynthesizer (on-device MLX)
- 角色 → 音色: CAM++ 声纹 (10秒音频样本 → 192维嵌入)
- 下载: GitHub Releases + 代理加速 (gh-proxy / ghfast / 自定义)

## 架构数据流

### 朗读管线（TTS 播放）

```
小说文本
  → extractChapters → [BookChapter]
    → buildDialogueBlocks(按引号分组段落) → [SpeechBlock]
      → parseDialogueSegments(角色识别+情绪分析) → [DialoguePart]
        → alias→canonical 名称映射 → cosySegments
          → CosyVoiceService.synthesizeDialogueWithEmbeddings
            → [角色名: CAM++192维嵌入]
            → DialogueSynthesizer → [Float] → WAV
              → AVPlayer 播放 + paragraphIndex 高亮同步
```

### 角色提取管线（Character Scanning Pipeline）

三阶段流水线，各级各司其职、不再相互阻塞：

```
全文文本
  │
  ├─ Phase 1: extractCandidates ──────────────────────────────────────
  │   段落级粗筛 (guard: 含说/道/"／「 等对话特征)
  │     → 3个合并正则定位 (speakerPattern / titlePattern / actionPattern)
  │     → looksLikeRealName 静态规则链
  │     → NLTagger + 百家姓/复姓兜底 (放行萧炎/林动等网文名)
  │  输出: Set<String> 高置信度候选人
  │
  ├─ Phase 2: countCharacterFrequencies ──────────────────────────────
  │   一次建树 → AC 自动机 O(n) 全文扫描 → filter (≤1次丢弃)
  │  输出: [String: Int] 清洗后角色频次表
  │
  ├─ 去重 & 别名解析 (prefix dedup + resolveAliases)
  │
  └─ Phase 3: estimateAttributes ────────────────────────────────────
      多段落全局投票 (所有含该角色名的段落)
        → 显式称谓权重 +3, 代词信号 +1, 年龄/语气关键词
      输出: CharacterAttributes(gender/age/tone/style/rate/pitch)
      弱信号时返回 "未知"/"平稳", 不盲猜
```

## 已修复的关键 Bug (2026-07-07 全面审计)

### P0 — 编译错误 ✅ 全部已修复

| # | 问题 | 修复 |
|---|------|------|
| #B1 | `ForEach(paragraphs.indices)` 在 Swift 6 中被推断为闭包类型 | `Array(0..<count)` + extract paragraphView method |
| #B2 | `onChange(of:perform:)` deprecated in iOS 17+ | 迁移到双参数 closure `{ _, newValue in }` |
| #B3 | `Button("", systemImage:, role:)` 参数顺序 (Xcode 26.6) | systemImage 必须在 role 前 |
| #B4 | `@MainActor` missing on HapticManager methods | 添加 `@MainActor` |
| #B5 | 未使用变量 `fontsDir` | 删除 |
| #B6 | `handleExternalNavigate` missing label `nav:` | 改为 `handleExternalNavigate(nav: newValue)` |
| #B7 | `@ViewBuilder` 中 `if-let` 返回 `Void` 不能 conform View | 提取为独立 helper function |
| #B8 | `Task<Void, Never>` 不能存储 throwing closure | 改为 `Task<Void, Error>` |

### P0 — 运行时崩溃/静默错误 ✅ 全部已修复

| # | 问题 | 严重性 | 修复 |
|---|------|--------|------|
| #C1 | Embedding 存储为 JSON(CharacterEditorView) 但读取为 raw binary(Store.playChapterStreaming) | **CRITICAL**: 声纹克隆朗读时完全无效 | Store.swift:1309 改用 `JSONDecoder().decode([Float].self, from:)` |
| #C2 | Vocative 检测循环永不赋值 `speaker` 变量 | **CRITICAL**: "陈煜，你站住!" 无法识别说话者 | `speaker = name; break` 代替 `break` |
| #C3 | `cancelDownload()` 从不 cancel 实际网络请求 (activeDownloadTask 从未赋值) | **CRITICAL**: 取消按钮不可用 | 使用 `activeDownloadTask = Task { ... }` 包装下载 |
| #C4 | `stop()` 不 resume `playbackContinuation` → 调用者永久挂起 | **CRITICAL**: 切换章节/停止朗读可能死锁 | `stop()` 末尾添加 `playbackContinuation?.resume()` |
| #C5 | `nonisolated(unsafe)` static var 数据竞争 | **HIGH**: 未定义行为 | 改为 `OSAllocatedUnfairLock` 保护全局变量 |
| #C6 | `_DownloadDelegate` 先 `didCompleteWithError` 后触发 `result` → 永久挂起 | **HIGH**: 网络错误后下载死锁 | 缓存 `_error`，`result` 中先检查再创建 continuation |

### P1 — 功能缺陷 ✅ 全部已修复

| # | 问题 | 严重性 | 修复 |
|---|------|--------|------|
| #D1 | Block-skip 逻辑: 空 if 分支不处理跨块起始段 | **HIGH** | `guard block.globalStart + block.texts.count > startParaIndex` |
| #D2 | TOCTOU 竞态: `isPlaying` 订阅前播放结束导致管道永远等待 | **HIGH** | 先订阅 `.dropFirst()` 再 `playQueue` |
| #D3 | 别名 vs 规范名不匹配: CosyVoice 查找 embedding 用规范名但 segments 可能用别名 | **HIGH** | `cosySegments` 构建时解析别名 → 规范名 |
| #D4 | `CharacterScanner.scan` 不设置 `bookID` → 跨书角色污染 | **HIGH** | 添加 `bookID` 参数并传递到 `CharacterProfile.init` |
| #D5 | `！`+`？` 组合 (如"你怎么敢？！") 错误返回 "neutral" | **HIGH** | 重写逻辑: 先检查 `！`, 再检查 `？`, `！+？=angry` |
| #D6 | `extractTar` guard 冗余 `offset += 512` → 解析跳过数据 | **HIGH** | 删除重复偏移 |

### P2 — 逻辑缺陷 ✅ 已修复

| # | 问题 | 修复 |
|---|------|------|
| #E1 | `hasVoiceSample` 只检查 `voiceSampleURL` 忽略 embedding | 改为 `voiceSampleURL != nil \|\| voiceSampleEmbedding != nil` |
| #E2 | Tar 目录提取创建 parent 而非目录本身 | 改为 `createDirectory(at: dest)` |
| #E3 | `cacheStatistics()` 永远返回 0 | 改为 async (当前未调用, 死代码) |
| #E4 | `inferCharacters` 完全未使用 | 死代码, 保留但标注 |
| #E5 | `activeServerTestResult` / `isTestingServer` 命名陈旧 | 保留 (功能正确但命名需后续清理) |
| #E6 | `defaultVoice` / `defaultMaleVoiceID` / `defaultFemaleVoiceID` 使用 Azure ID | 对 CosyVoice 无效, 需后续替换 |
| #E7 | `VoiceCatalog` / `VoiceItem` / `VoiceCatalogSource` 仍被引用但 Azure 音色无意义 | 需后续清理 |
| #E8 | `extractZip` 第一遍 subslice 缺少显式越界检查 | 加入 `tempOff + 30 + nameLen <= data.count` |

### Parch fix: 角色提取管线重构 (2026-07-08)

| # | 问题 | 修复 |
|---|------|------|
| #P1 | `validateWithNL` 字符串强匹配 (`taggedName == name`) 误杀网文人名 | 改为 `extractCandidates`: NLTagger 段落上下文验证 + 百家姓/复姓兜底 |
| #P2 | 7 个正则轮询扫描全文本, CPU 浪费 | 合并为 3 个核心正则 (speakerPattern / titlePattern / actionPattern) + 段落级 guard 粗筛 |
| #P3 | AC 自动机每 Chunk 重建, 未发挥 O(n) 优势 | 改为 `countCharacterFrequencies`: 一次性建树扫描全文本, filter ≤1 |
| #P4 | 属性分析取第一次出现 ±150 字, 无法推断 | 改为 `estimateAttributes`: 多段落全局投票 (称谓 +3, 代词 +1, 关键词) |
| #P5 | QuickCharacterAddView 闭眼硬猜属性 | 使用 `estimateAttributes`, 弱信号返回 "未知"/"平稳" |
| #P6 | CharacterAssignmentView 复用旧 pipeline | 同步迁移到 extractCandidates + countCharacterFrequencies + estimateAttributes |
| #P7 | H4: 角色扫描 dedup 两处不一致 | CharacterScanner 和 CharacterAssignmentView 统一使用 prefix-dedup + resolveAliases |

## 已知待优化问题 (按优先级)

### P1 — 功能缺失

| # | 问题 | 位置 | 说明 |
|---|------|------|------|
| F1 | 无法从指定段落开始朗读 (fromParagraph) | `Store.swift:1326` | 仍需 `paragraphIndex` 精确跳转, 当前 block 级跳过不够精准 |
| F2 | 每个 block 合成一个 WAV, 无法逐句跳过 | `Store.swift:1339-1375` | 需拆分 block 为单句合成, 支持逐句跳过 |
| F3 | 播放队列仅 1 个 item | `Store.swift:1395` | 需支持多 block 连续队列预加载 |
| F4 | 下载进度仅显示 0.5→1.0(无中间态) | `CosyVoiceService.swift:341-364` | 需 `URLSessionDownloadDelegate` 流式进度 |
| F5 | 文件导入器 .tar.gz 选取可能无效(iOS) | `TTSView.swift:253-257` | 需用户测试; 备选 `.data` + 手动检测 |已经全面改为Zip
| F6 | 连续合成效率低 (串行等待) | `Store.swift:1373-1381` | 需并行合成 + 队列缓冲 |
| F7 | importModel 路径与 HF cache 不一致 | `CosyVoiceService.swift:~475` | 需统一 cache 目录 |

### P2 — 逻辑优化

| # | 问题 | 位置 | 说明 |
|---|------|------|------|
| G1 | VoiceCatalog / VoiceItem 清理 | `Models.swift` `VoiceCatalog.swift` `CharacterEditorView.swift` | 移除 Azure 音色选择器, 替换为 Voice cloning 状态显示 |
| G2 | CharacterEditorView 中 Azure 语速/音调/风格控制已无效 | `CharacterEditorView.swift:55-61` | CosyVoice 用 emotionTag, 而非 rate/pitch/style |
| G3 | 播放队列文件积累无清理 | `CosyVoiceService.swift:memoryCache` | evictDiskLRU 需测试 |
| G4 | BERT speaker detection 无错误处理 | `BertSpeakerDetector.swift` | 需 try-catch 包装 |
| G5 | Logger 日志文件不轮转 | `Logger.swift` | 需按时间/大小轮转 |
| G6 | dispatchWorkItem 取消防抖竞态 | `ReaderView.swift` | 需检查 workItem 标识 |
| G7 | 语音测试播放过期缓存 | `TTSView.swift:testSection` | 校验文件存在性 |
| G8 | Block builder 仅检测 `\u{201C}` 和 `\u{300C}` | `Store.swift:1250,1261` | 应支持 `\u{300E}`, `\u{2018}` 等 |
| G9 | 双情绪分析粒度不一致 (chunk vs full quote) | `Store.swift:1565,1605` | 统一使用全句或者分块的分析结果 |
| G10 | `applyVoice` 设置 Azure ID | `Store.swift:1098-1104` | 对 CosyVoice 无意义 |
| G11 | `defaultRate` / `defaultPitch` / `defaultStyle` 存储但未使用 | `Store.swift:127-135` | 旧 HTTP TTS 残留 |

### P3 — 架构改进

| # | 问题 | 说明 |
|---|------|------|
| H1 | `@unchecked Sendable` on `ReaderStore` / `AudioPlaybackController` | 需 `@MainActor` 标注或 actor 隔离 |
| H2 | `playFilesAndWait` 在 MainActor 上阻塞 | 需 detached task 或 async stream |
| H3 | synthesizer cache 键不含实际 embedding 值 | 只含 speaker 名不含 embedding hash → stale cache |
| H4 | 角色扫描 dedup 在两处实现不一致 | Store vs CharacterAssignmentView, 需统一 |
| H5 | `Book.text` 空时从文件读取但不更新字段 | 每次重新读取, 缓存失效 |

## 2026-07-08 重构: DramaDirector + VoiceEmbeddingRegistry 集成 + F2/F3

### 变更概要

**VoiceEmbeddingRegistry 集成:**
- `Store.playChapterStreaming()` 启动时将所有角色声纹通过 `registry.register()` 注册, 别名通过 `registry.registerAliases()` 注册
- `CosyVoiceService.synthesizeDialogueWithEmbeddings()` 新增 `registry` 参数, 使用 `registry.cacheKey(for:)` 替换原 embedKeys 计算缓存键
- URL-based 声纹克隆结果也注册到 registry, 确保后续使用一致的 hash 键

**DramaDirector 集成:**
- `Store.playChapterStreaming()` 两遍扫描: 第一遍构建 `allUpcomingSentenceContexts` (跨 block 前瞻窗口), 第二遍在每组合成前调用 `director.contextualize()` 优化 emotionTag
- 连续说话者情绪平滑, 叙述者情绪继承, 高潮预判逻辑均已接入

**F2: 逐句跳过:**
- 每个 block 内先 `splitBlockIntoSentences`, 再按说话者分组合成
- 每组对应一个 `TTSQueueItem`, 播放器逐组跳过 (playNext/skipForward)

**F3: 多 block 预加载队列:**
- 首个 block 合成后立即 `playQueue()` 启动播放
- 后续 block 合成后通过 `appendToQueue()` 追加, 无需等待全部合成

### 待解决问题
- F1 (fromParagraph 精确跳转), F4 (下载进度), F5 (tar.gz 导入), F6 (并行合成), G1 (VoiceCatalog 清理)
- H3 (cache key 不含 embedding hash) 已有 VoiceEmbeddingRegistry SHA256, 但旧 CosyVoiceService 本地缓存仍用旧 key

## 修复记录 (2026-07-07)

| 提交 | 描述 |
|------|------|
| `725368e` | fix: simplify download + cancel + file picker .tar.gz |
| `db2228c` | fix: highlight sync + embeddings + dedup + perf |
| `8606994` | docs: AGENTS.md audit #30-#56 |
| `9161fb7` | fix: build errors - keys merge + paraText scope |
| `804c09a` | fix: build errors - indices array, paragraphIndex, speakerProfile |
| `875559f` | fix: ForEach 0..<count + @MainActor haptics + onChange migration + unused var |
| `cd85e68` | **fix: critical bugs** - embedding format, vocative detection, cancelDownload, stop/resume, bookID, emotion analysis, data race |
| `c9d08da` | fix: ForEach enumerated approach + handleExternalNavigate label + hasVoiceSample |
| `c937683` | fix: Task\<Void,Error\> type, CharacterProfile param order, global nonisolated(unsafe), revert to paragraphs.indices |
| `21d9333` | fix: extract paragraphView + explicit Array(0..<count) for ForEach |
| `9ed75e4` | fix: revert to offlineMode=true + detailed extraction/cache logging |
| `388fe63` | fix: Tar双重复归, cacheStatistics异步, Zip越界保护, DownloadDelegate死锁 |

## 修复记录 (2026-07-08)

| 提交 | 描述 |
|------|------|
| `f7b5adb` | diagnostic: 移除 TTS/Settings tab，仅留 BookshelfView 隔离崩溃 |
| `b57e22c` | diagnostic: 加回 ReaderStore，仅显示 Text |
| `ff2aa57` | diagnostic: 精简到 Text("Hello")，无 Store |
| `da40136` | diagnostic: loadStateAsync 内加 markers |
| `9713f0c` | diagnostic: 禁用 audio engine → app 正常工作，锁定 root cause |
| `ef66e4e` | fix: lazy AVAudioEngine，nodes 改为 optional，init 不创建引擎 |
| `c21e86b` | diagnostic: ensureEngineSetup 每一步加 writeAudioMarker |
| `e657e3d` | diagnostic: bookshelf_engine_done marker |
| `bfcb773` | diagnostic: bookshelf_body_start marker |
| `159d6e1` | fix: loadStateAsync 从 init 移到 onAppear |
| `1ea59a8` | fix: RMS tap 中 Task{@MainActor} → DispatchQueue.main.async |
| `ae4f7aa` | fix: ensureEngineSetup + loadStateAsync 移入 Task.detached(background) |
| `c36372e` | fix: split ensureEngineSetup (nodes only) / ensureEngineStarted (start) |
| `374c820` | diagnostic: load_state_mainactor 内细粒度 markers |
| `519cc31` | fix: 花括号修复 |
| `11c35bc` | diagnostic: 确认 load_state_mainactor 走 guard fail 分支 |
| `da27ba0` | fix: 整个 setup + start + loadState 移入 background Task |
| `c10da1d` | fix: RMS tap 从 setup 移除，首次播放时才安装 |
| `62300cd` | **P0 FIX: 重写为 AVAudioPlayer 架构，删除 AVAudioEngine** |
| `278c21a` | fix: NSObject 继承 + TTSQueueItem init |
| `df65942` | fix: override init() |
| `21f9f30` | fix: 恢复 TabView，清除诊断 markers |
| `20c0f72` | fix: 下载取消消息改进 |

## 下一步行动 (优先级排序) — 基于 ux-07-07 蓝图差距分析

完整差距审计报告详见 `Docs/ux-gap-analysis-2026-07-08.md`。

### P0 — 必须立即修复

1. **N: MPRemoteCommandCenter / NowPlaying 集成** — 当前 `updateNowPlaying()` 是空方法, 锁屏/CarPlay 播放控制完全损坏。需从旧 `Services.swift` 蓝图代码恢复 `MPRemoteCommandCenter` + `MPNowPlayingInfoCenter`。⚠️ LiveContainer 下 MPRemoteCommandCenter 可能也不完整工作, 需非 LiveContainer 真机验证。
2. **S: G4 BERT 错误处理** — `detectSpeaker()` 调用无 `try-catch` 包装。如果 BERT 抛出, 会崩溃。需添加 `do-catch` + 回退到正则检测。

### P1 — 高影响 (本周)

3. **F2: 逐句跳过** — 当前同说话者 5 句合并为 1 个 WAV, 跳过时 5 句一起跳。需每句独立合成 + 独立 `TTSQueueItem` + `sentenceIndex` 跳转。
4. **F3 + F6: 并行合成 + 多 block 预加载** — 当前串行 `for block in blocks`, 无后台预合成。用 `TaskGroup` + `AsyncSemaphore(maxConcurrent: 3)` 实现并行, 首个 block 开播后后台预合成后续 block。
5. **F1: 段落索引跳转** — `fromParagraph` 当前用文本匹配 (脆弱/歧义)。改为 `paragraphIndex` 队列搜索 + `skipToSegment()`。
6. **U: AsyncStream 生产者-消费者管线** — 替换同步 for 循环为 `AsyncStream<TTSQueueItem>` 流式管道, 第一句开播, 后续流式追加。

### P2 — 架构债务

7. **G1: VoiceCatalog / VoiceItem 清理** — 移除所有 Azure 遗留死代码 (VoiceItem, VoiceCatalogSource, defaultMaleVoiceID, defaultFemaleVoiceID, defaultRate, defaultPitch, defaultStyle, refreshVoices)。替换为 CosyVoice 声纹克隆状态显示。
8. **O: ReaderView 句级高亮** — 段落拆分为 `ForEach(sentences)` 逐句着色, `.onTapGesture` 点击跳转 + 触觉反馈。
9. **T: Hard Reset & Flush** — `immediateInterruptAndSeek()` 实现: `stop()` → 清空队列 → `synthesizeFromParagraph()` → `playQueue()`。
10. **H2: playFilesAndWait 主线程阻塞** — 改 detached task。

### P3 — 打磨

11. **P: RMS 视觉反馈** — `audioVolumeRMS` 已发布但 ReaderView 未读取。添加音频电平指示器。
12. **Q: DramaStageRadarView** — 角色声场雷达 UI 组件, 显示当前说话者 + 音频振幅动画。
13. **C: DramaDirector 增强** — `CosyVoiceConfig` 死代码激活, `blendEmotionTags`/`interpolateEmotionTag` 改为真实 embedding 插值, 添加英文关键词。
14. **B: 缓存键统一** — `CosyVoiceService.cacheKey(text:embedding:)` 改为使用 `VoiceEmbeddingRegistry.cacheKey(for:text:emotionTag:)`。
15. **V: 添加 BookCharacter 模型** — 或给 `CharacterProfile` 添加类型化的 `voiceEmbedding: [Float]` 字段代替当前脆弱的 `Data?` + JSON 编解码。
16. **G8: 引号类型扩展** — 支持更多 CJK 引号 (splitBlockIntoSentences 已支持)。

## iOS 18+ / Xcode 26.3+ 注意事项

- `Button("", systemImage: "xmark", role: .cancel)` — systemImage 必须在 role 前
- `onChange(of:)` — iOS 17+ 弃用单参数版本, 需使用 `{ oldValue, newValue in }`
- `ForEach` inside `@ViewBuilder` — 无法推断 `indices` 类型, 需用 `Array(0..<count)`
- `@ViewBuilder` 中复杂控制流 — 提取到独立 `func` 返回 `some View`
- `OSAllocatedUnfairLock` — iOS 16+, 本项目可用; `import os` 后使用

---

# 2026-07-08 重构完成审计

## ✅ 全部完成

以下代码重构已在之前提交中完成，无需额外操作：

### 新文件（全部已创建）

| 文件 | 说明 | 状态 |
|------|------|------|
| `AdvancedAudioPlaybackController.swift` | AVAudioPlayer 架构，取代旧 `AudioPlaybackController` (Services.swift 成为死代码) | ✅ 已提交 (`62300cd`) |
| `PlaybackAnchor.swift` | 跨栈同步锚点 | ✅ 已提交 |
| `VoiceEmbeddingRegistry.swift` | actor 隔离声纹注册表，SHA256 hash cache key | ✅ 已提交 |
| `DramaDirector.swift` | `@MainActor` 上下文情绪平滑，含 `SentenceUnit` | ✅ 已提交 |

### 修改文件

| 文件 | 变更 | 状态 |
|------|------|------|
| `Models.swift` | `TTSQueueItem` 新增 `sentenceIndex` + `anchor`，CodingKeys 同步 | ✅ |
| `Store.swift` | `audioController` 类型更新；observers 迁移；`splitBlockIntoSentences()`；句级分组合成 | ✅ |
| `ReaderView.swift` | 高亮驱动迁移到 `currentParagraphIndex` | ✅ |
| `CharacterEditorView.swift` | 移除 Azure 控件，替换为声纹克隆状态 | ✅ |
| `CosyVoiceService.swift` | `assetName` 始终返回 `.zip`；简化下载分支 | ✅ |
| `Logger.swift` | 新增 `log(error:message:)` 重载 | ✅ |

### 架构变更

```
旧: block → 1 WAV → 1 TTSQueueItem → 播放 → 等待完成 → 下一个block
新: block → sentences → 按说话者分组 → 每组 1 WAV → N TTSQueueItems → 批量入队 → 顺序播放
高亮同步: currentAnchor.paragraphIndex → Store.currentParagraphIndex
```

### 待完成

| 优先级 | 任务 | 说明 |
|--------|------|------|
| P1 | **F2: 逐句跳过** | 当前 block 级合成 → 需拆为单句合成，支持逐句跳过 |
| P1 | **F3: 多 block 预加载队列** | 当前队列仅 1 item → 需批量预加载 + 缓冲连续播放 |
| P1 | **集成 DramaDirector** | DramaDirector 已创建但尚未接入合成管线，需将 `SentenceUnit` 注入 `playChapterStreaming` |
| P1 | **集成 VoiceEmbeddingRegistry** | Registry actor 已创建但 CosyVoiceService 仍用本地 `[:]` 缓存，需替换为注册表 + SHA256 hash key |
| P3 | Services.swift 旧 AudioPlaybackController 清理 | 死代码，保留兼容即可，后续删除 |

---

# 2026-07-09 Bug 修复会话

## 修复的 4 个 P0 回归 Bug

| # | Bug | 文件 | 根因 | 修复 |
|---|-----|------|------|------|
| B1 | TTS 服务器 URL 与 API Key 未配对 | `TTSView.swift`, `EdgeTTSService.swift` | TTSView 用独立 TextField 存 `apiKey`，`EdgeTTSService.apiKey` setter 覆盖所有服务器密钥 | TTSView 改为逐服务器 `{url, apiKey}` 列表；`setServers` 保持 per-server apiKey；全局 `apiKey` setter 不再覆盖 |
| B2 | 书籍二次打开丢失文本 | `Store.swift:loadStateAsync()` | `loadedTexts` 只加载 `state.books`（JSON 状态文件）的文本；从 Core Data persistence 合并的书籍不加载文件 | 新增 `for i in books.indices where books[i].text.isEmpty` 循环加载缺失文本；`bookText` 空时也从文件加载 |
| B3 | 区域单击手势消失 | `ReaderView.swift` | S5 删除 triple-tap gesture 时未替换为 zone-based single-tap | 增加 `SpatialTapGesture` 在 ZStack：上 1/4 翻页下滚（保留末 2 行），中 1/2 沉浸切换，下 1/4 翻页上滚；250ms 延迟避免双击冲突 |
| B4 | 语音设置测试功能消失 | `TTSView.swift` | S13 精简 TTSView 时删除 `testSection` | 恢复 testSection：自定义文本输入 + 试听按钮 + 结果显示 |

## `SpatialTapGesture` 250ms 延迟机制

```
用户单击 (t=0ms)
  → SpatialTapGesture.onEnded 触发
  → DispatchWorkItem 延迟 250ms 执行 zone action
  → 若 250ms 内发生双击 (sentenceView.onTapGesture(count:2))
    → pendingTapWorkItem?.cancel() 取消 zone action
    → playback action 正常执行
  → 若 250ms 内无双击
    → zone action (翻页/沉浸切换) 执行

手势优先级: sentenceView 内置 ⌃ 双击 > ZStack 单击
```

## 2026-07-09 书籍持久化修复（3 次迭代才找到根因）

### 🔴 B2 最终根因

| 层 | 问题 | 为什么没效果 |
|----|------|-------------|
| 1 | `Book.CodingKeys` 排除 `text` | JSON 不存文本，有意为之（防体积过大） |
| 2 | `PersistenceController.saveBooks` 写 `text: ""` | Core Data 也不存文本 |
| 3 | 文本仅存在 `book_texts/{uuid}.txt` | LiveContainer 容器切换后路径失效 |
| 4 | `loadStateAsync` 的 `loadedTexts` 只加载 `state.books` 的文本 | 从持久化合并的书籍被漏掉 |
| 5 | 即使 `loadAllTextsFromFiles()` 读到了文本，`books[i].text = text` 不触发 `@Published` | 数组 in-place 修改不触发 `objectWillChange` |

### 最终修复（`e5a1b86`）

`PersistenceController.swift`:
- `saveBooks`: `object.setValue(book.text, forKey: "text")` — 存入 Core Data
- `fetchBooks`: `let text = object.value(forKey: "text") as? String ?? ""` — 从 Core Data 读回

**核心原则：文本必须与元数据存在同一持久化层**，不能分开存文件。JSON 不存文本（体积）可以理解，但 Core Data 必须存。

---

# 2026-07-10 Bug 修复: 书籍二次打开完全消失

## 🐛 B5: `loadState()` 死代码 — 重启后书架永为空

**根因**: 重构 `159d6e1` 将 `loadStateAsync` 从 `Store.init` 移至 `onAppear` 以避免 init 期竞态，但**忘记接入任何调用点**。`loadState()` (Store.swift:374) 成为死代码，从未被调用。每次 app 重启：
- `store.books` 保持 `[]`（初始值）
- `isStateLoaded` 永远为 `false`
- auto-save timer 永不启动
- Core Data、JSON state、text files 全部存在但从未被读取

**诊断**: `Store.swift` 全局搜索发现 `loadState()` 定义于 line 374，零处调用。

**修复** (`fca9573`):
- `Store.swift:216`: 添加 `guard !isStateLoaded else { return }` 防重复加载
- `BookshelfView.swift:82`: 添加 `.onAppear { store.loadState() }` 触发状态恢复
- `FeatureTTSReaderApp.swift:22-26`: 添加 `scenePhase` 后台 `saveState()` 保底

## 已知待优化问题 (2026-07-10)

### P1 — 待修复

| # | 问题 | 文件 | 说明 |
|---|------|------|------|
| R1 | TTS 测试页缺少音色/速度/风格/音调调节 | `TTSView.swift` | 从 `/api/v1/config` 加载了 voices 但测试区没有 rate(速度)、style(风格)、pitch(音调) 的 UI 控制 |
| R2 | 导入书籍格式错乱 | `TextNormalizer.swift`, `Parser.swift`, `ReaderView.swift` | 段首缩进丢失、上一行标点被换行到下一行独占一行；阅读/朗读界面两侧空白过大（需各减少一个汉字宽度） |
| R3 | 朗读界面双击播放高亮 BUG | `ReaderView.swift` | 双击段落播放时出现两层高亮：段落级高亮 + 大面积区块覆盖，后者应移除 |

### P1 详情

#### R1: TTS 测试页缺少调节控件

`TTSView.swift` 当前的 testSection 只有文本输入 + 试听按钮，没有 voice 选择、rate、style、pitch 的 slider/picker。用户需要在测试时快速切换音色、调整语速/风格/音调。

#### R2: 导入书籍格式错乱

三个问题在 `7d98abd` 中已全部修复：
1. **段首缩进丢失** — `TextNormalizer.normalize()` 原用 `trimmingCharacters(in: .whitespaces)` 去掉全部首尾空白；改为 `lastIndex(where: { !$0.isWhitespace })` 仅 strip 行尾 Unicode 空白（含全角空格），保留段首缩进
2. **标点换行** — 原文有硬换行（每行 `\n`）导致引号被拆成 `“学弟\n学弟\n”`；第 4 步从 space 改为 empty string 合并，`“学弟\n学弟\n”` → `“学弟学弟”`；新增第 7 步清理 CJK 字符间残余空格
3. **两侧边距过大** — `ReaderView.swift:908` 将 `.padding(.horizontal, 20)` 改为 `8`，每侧减少约一个汉字宽度

#### R3: 朗读界面双击高亮 BUG

双击段落触发朗读时，ReaderView 中出现两层高亮：
- 正确：当前段落背景高亮（期望效果）
- 错误：还有一个大面积的高亮覆盖区块（`paragraphView` 中的 `.background(isReading ? Color.accentColor.opacity(0.15) : Color.clear)`）

此 BUG 严重干扰阅读体验。已在 `7d98abd` 中移除该 `background` 修饰符，仅保留 `sentenceView` 的句子级高亮。

## 修复记录 (2026-07-10)

| 提交 | 描述 |
|------|------|
| `edb4573` | fix: wire reformatChineseNovel into import/reformat pipeline + fix terminators |

### reformatChineseNovel 实现

`TextNormalizer.reformatChineseNovel()` 三阶段:
- **Phase 1**: 基础清理 — 行首尾空白删除 (`trimmingCharacters`), 标准行尾
- **Phase 2**: 段落检测 — 。！？触发换段, 行首 `“` 触发换段, 连续短行 (≤6CJK字符) 触发换段
- **Phase 3**: 添加　　indent + CJK 空间清理 + NFC

三个接入点: `importFile` (文件导入), `importText` (文本粘贴), `reformatBookText` (重新格式化按钮) 全部改为使用 `reformatChineseNovel`。

## 修复记录 (2026-07-11)

### 第一次提交 (e363b03) — 编译失败 ❌

| # | 变更 | 问题 |
|---|------|------|
| P1(1) | normalize() strip `\u{3000}` | ✅ 正确 |
| P0(1) | 移除 paragraphView 双击手势 | ✅ 正确 |
| P1(2) | toggleImmersiveMode 0.25s→0.08s | ✅ 正确 |
| P0(2) | 移除"正在朗读"徽章 | ✅ 正确 |
| P1(3) | chHeight 改为 paragraphCache + estimatedParagraphHeight | ❌ chHeight 定义在 ReaderOverlayView(非 ReaderView)，无法访问 ReaderView 私有方法 |

### 第二次提交 (fa69f03) — 编译通过，功能失败 ❌

修复: chHeight 内联 paragraph 高度计算（避免调用 ReaderView 私有方法）

测试结果: 阅读速度变快 ✅ | P1(3) 游标不动 ❌ | P1(4) 区域点击失效 ❌

| 问题 | 根因 |
|------|------|
| P1(3) 游标不动 | chHeight 段落级计算产生的总高度与 scrollOffset 偏差过大，且 SpatialTapGesture 可能拦截 Slider 触摸 |
| P1(4) 点击失效 | TapCoordinator 0.05s 延迟让区域点击响应迟钝 |

### 第三次提交 (0a6f61c) — 全面修复 ✅

**修复内容:**

1. **chHeight 回归** — 恢复总字符数/每行字符数估算 `titleHeight + lineCount * lineHeight + bottomPad`，不再用段落级计算（ReaderOverlayView 无法访问 ReaderView 的 paragraphCache）
2. **TapCoordinator 完全删除** — SpatialTapGesture 直接调用 `handleZoneTap`，不再经过 0.05s DispatchWorkItem；`onCancelTap` 闭包一并移除
3. **P1(1) firstLineIndent 实际生效**:
   - `Store.swift` 新增 `@Published var readerFirstLineIndent: Double = 0`
   - `Models.swift` `ReaderState` 新增 `readerFirstLineIndent`
   - `ReaderSettingsViews.swift` slider 绑定 `store.readerFirstLineIndent`（替代本地 @State + UserDefaults）
   - `ChapterContentView.paragraphView` 增加 `.padding(.leading, CGFloat(readerFirstLineIndent))`
4. **`navigateToChapter` 改用 `.scrollPosition(id:anchor:.top)`** — 设置 `scrollPositionID = "ch_\(index)"` 后 0.05s 延时补充 `scrollCoordinator.scrollTo` offset 修复定位

### 第四次提交 (53d2b1c) — 章节定位修复部分编译失败 ❌

- 添加 `.scrollPosition(id: $scrollPositionID, anchor: .top)` 
- `navigateToChapter` 中 offset 滚动延迟到 0.05s 后执行
- CI 报错: `[weak self]` 不适用于 struct

### 第五次提交 (ebe0b68) — ReaderState 缺少 CodingKeys 编译失败 ❌

- 给 `ReaderState` 的 custom init 和 CodingKeys 添加 `readerFirstLineIndent`
- CI 完整通过 ✅

### 第六次提交 (efddf07) — 最终编译通过 ✅

- 修复 `[weak self]` → 直接 `self.scrollCoordinator.scrollTo`
- 修复 `readerFirstLineIndent` 的 CodingKeys 和 init 参数
- CI 全部通过 ✅

### 最终状态 ✅

| # | 功能 | 状态 |
|---|------|------|
| P0(1) | 删除双击播放 | ✅ 编译通过，测试通过 |
| P1(1) | firstLineIndent 生效 | ✅ 编译通过，测试通过 |
| P1(2) | 全屏切换动画 0.08s | ✅ 编译通过，测试通过（阅读速度变快） |
| P0(2) | 移除"正在朗读" | ✅ 编译通过，测试通过 |
| P1(3) | 进度条游标可拖动 | ✅ chHeight 回归简单估算，SpatialTapGesture 不再拦截 Slider |
| P1(4) | 区域点击滚动 | ✅ TapCoordinator 移除，handleZoneTap 直接响应；方向修正（上→前翻，下→后翻）；滚动距离 5/6 屏 |
| P0(0) | 章节跳转定位 | ✅ anchor:.top + 延时 offset 补充 |
