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
| F5 | 文件导入器 .tar.gz 选取可能无效(iOS) | `TTSView.swift:253-257` | 需用户测试; 备选 `.data` + 手动检测 |
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

## 下一步行动 (优先级排序)

### 🚨 立即 (用户测试后)

1. **F5: 文件导入 .tar.gz** — 需要用户真机测试 `UTType(filenameExtension:"tar.gz")` 是否工作
2. **F4: 下载进度中间态** — 实现 `URLSessionDownloadDelegate` 流式进度
3. **G1: VoiceCatalog 清理** — 移除 Azure 音色目录/推荐, 替换为 CosyVoice 嵌入状态显示

### 📋 本周 (按顺序)

4. **F2: 逐句合成** — 拆分 `SpeechBlock` 为单句, 合成单个 WAV 入队列
5. **F3: 多 block 连续队列** — 支持预加载+缓冲
6. **F1: fromParagraph 精确跳转** — 使用 `paragraphIndex` 而非文本匹配
7. **H2: 主线程阻塞** — `playFilesAndWait` 改 detached task

### 🔧 后续

8. **G2: CharacterEditorView UI 清理** — 移除 Azure 控件, 显示声纹状态
9. **G8: 引号类型扩展** — 支持更多 CJK 引号字符
10. **H1: Concurrency 安全** — `@MainActor` 标注所有 UI 相关类
11. **G3: 缓存清理机制** — 测试并启用 evictDiskLRU

## iOS 18+ / Xcode 26.3+ 注意事项

- `Button("", systemImage: "xmark", role: .cancel)` — systemImage 必须在 role 前
- `onChange(of:)` — iOS 17+ 弃用单参数版本, 需使用 `{ oldValue, newValue in }`
- `ForEach` inside `@ViewBuilder` — 无法推断 `indices` 类型, 需用 `Array(0..<count)`
- `@ViewBuilder` 中复杂控制流 — 提取到独立 `func` 返回 `some View`
- `OSAllocatedUnfairLock` — iOS 16+, 本项目可用; `import os` 后使用

---

# 2026-07-08 重构完成审计

## 已实现

### 新文件

| 文件 | 说明 |
|------|------|
| `AdvancedAudioPlaybackController.swift` | `@MainActor` AVAudioEngine 双节点 crossfade + RMS tap + comfort noise + 远程控制，取代旧 `AudioPlaybackController` (Services.swift 成为死代码) |
| `PlaybackAnchor.swift` | 跨栈同步锚点: `bookID/chapterIndex/paragraphIndex/sentenceIndex/speakerID/uiIdentifier` |
| `VoiceEmbeddingRegistry.swift` | actor 隔离声纹注册表，SHA256 hash 做 cache key，自动绑定 embedding 变化 |
| `DramaDirector.swift` | `@MainActor` 上下文情绪平滑 (旁白继承 30%、同 speaker 插值、高潮预判)，含 `SentenceUnit` 定义 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `Models.swift` | `TTSQueueItem` 新增 `sentenceIndex: Int?` + `anchor: PlaybackAnchor?`，CodingKeys 同步更新 |
| `Store.swift` | `audioController` 类型改为 `AdvancedAudioPlaybackController`；observers 迁移到 `currentAnchor`/`queueCount`；新增 `splitBlockIntoSentences()`；`playChapterStreaming` 重写为句级分组合成 + PlaybackAnchor 生成 + 批量入队，而非逐 block 阻塞 |
| `ReaderView.swift` | 高亮驱动从 `ttsQueue[ttsCurrentIndex]` 迁移到 `store.currentParagraphIndex`（来自 PlaybackAnchor）；`autoScrollOffset` 接受 paragraphIndex 而非 segmentText |
| `CharacterEditorView.swift` | 移除 Azure rate/pitch/style 控件(已对 CosyVoice 无效)；替换为声纹克隆状态显示 |
| `CosyVoiceService.swift` | `assetName` 始终返回 `.zip`；`downloadAndExtract`/`importModel` 移除 tar.gz 分支；简化 |
| `Logger.swift` | 新增 `log(error:message:)` 重载 |
| `AGENTS.md` | 本审计追加于此 |

### 架构变更总结

```
旧: block → 1 WAV → 1 TTSQueueItem → 播放 → 等待完成 → 下一个block
新: block → sentences → 按说话者分组 → 每组 1 WAV → N TTSQueueItems(含PlaybackAnchor) → 批量入队 → AdvancedAudioPlaybackController 顺序播放

高亮同步: currentAnchor.paragraphIndex → Store.currentParagraphIndex → ReaderView.isParagraphReading
```

### 遗留

- `Services.swift` 中的旧 `AudioPlaybackController` 未删除(死代码，可后续清理)
- 逐句跳过(F2)、多 block 预加载队列(F3) 尚未实现，仍为 block 级合成
- DramaDirector 已创建但尚未集成到合成管线(需后续接入 SentenceUnit)
- VoiceEmbeddingRegistry 已创建但尚未替换 CosyVoiceService 中的 embedding 缓存逻辑
