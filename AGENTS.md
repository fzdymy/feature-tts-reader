# FeatureTTSReader — On-Device Multi-Role TTS 集成计划

## 现状 (2026-07)

- iOS 18+ / Swift 5.9 / SwiftUI
- 角色检测: BERT embedding + 余弦相似度 (77% 准确率)
- TTS: HTTP 客户端 → 本地服务器 (Edge-TTS/GPT-SoVITS)
- 角色 → 音色: Azure TTS 音色 ID, rate/pitch/style 参数

## 目标架构

```
小说文本
  → BERT 角色检测 (已有, 确定每句对白的角色)
  → analyzeSentenceTone (已有, 确定每句情绪)
  → 拼接: "[陈煜] (angry) 你这个小偷！"
  → CosyVoice 3 DialogueSynthesizer (on-device MLX)
    → 每个角色: CAM++ 声纹 (10秒音频样本 → 192维嵌入)
  → 24kHz 音频 → AVPlayer 播放
```

## 阶段

### Phase 0: 基础设施 ✅ (已完成)
- [x] `Scripts/convert_distilbert.py` — BERT 转 Core ML
- [x] `.github/workflows/convert-ml-model.yml` — CI 转换流水线
- [x] `BertSpeakerDetector.swift` — 角色检测嵌入模型
- [x] `Package.swift` — BERT 模型资源

### Phase 1: 代码清理 ✅ (已完成)
- [x] 更新 `Package.swift` 加 speech-swift 依赖 (删 VoiceCatalog 待 Phase 5)
- [x] 更新 `Models.swift`:
  - `CharacterProfile` 加 `voiceSampleURL` / `voiceSampleEmbedding`
  - 删除错误重复的 TTSServer/VoiceProfileTuning/TagPreset/RoleTemplate 定义
- [x] 删 `Services.swift` 中的 `TTSHttpClient` (保留 AudioPlaybackController/AsyncSemaphore)
- [x] 删 `TTSServerListView.swift`, `VoiceFineTuneView.swift`
- [x] `TTSView.swift` → 重写为 CosyVoice 状态页 (移除旧 UI)

### Phase 2: CosyVoice 引擎 ✅ (已完成)
- [x] 创建 `CosyVoiceService.swift`:
  - 封装 `CosyVoiceTTSModel.fromPretrained()` + 懒加载
  - CAM++ 声纹提取 (`CamPlusPlusSpeaker`)
  - `synthesizeDialogue(segments:speakerSamples:)` → `Data` (WAV)
  - `synthesizeSingle(text:embedding:)` 单句预览
  - 内建 `AudioConverter.floatToWAV()` 将 [Float] → WAV
- [x] 更新 `Store.swift`:
  - `playChapterStreaming` 用 `CosyVoiceService.shared.synthesizeDialogue` 替换 HTTP TTS
  - `previewVoice` 用 `CosyVoiceService.shared.synthesizeSingle` 替换 HTTP
  - `testActiveServer` / `testTTSSynthesize` → 切换至 CosyVoice 检测
  - 删 `client` 属性 (TTSHttpClient), 删 `loadTTSServers`/`loadVoiceProfiles` 等加载逻辑
  - `playChapterWithTTS` → 简化为重定向到 `playChapterStreaming`
  - 删 `playScriptSegments` (旧批量 HTTP 合成逻辑)
  - `CharacterEditorView`/`CharacterAssignmentView` TTS sample → CosyVoice

### Phase 3: 管道对接 ✅ (已完成)
- [x] `DialoguePart` 新增 `emotionTag: String?` 字段
- [x] `parseDialogueSegments` → 对话部分调用 `analyzeSentenceTone` → 映射到 CosyVoice 情绪标签 (angry/happy/sad/nil)
- [x] 情绪标签映射: `mapToneToEmotionTag()` 在 `Store.swift`
- [x] `createScriptSegments` → 传递 `emotionTag` 到 `ScriptSegment`
- [ ] TTS 缓存: 按 embedding+text hash (待后续优化)

### Phase 4: UI 更新 ✅ (已完成)
- [x] `SettingsView.swift`: 加 CosyVoice 状态, 删 TTS 服务器设置 (已无相关 UI)
- [x] `CharacterEditorView.swift`: 加音频样本录制/导入 (WAV 录制 + 文件导入 + 声纹提取)
- [x] `CharacterAssignmentView.swift`: 显示声纹状态 (context menu 生成试听使用 CosyVoice)
- [x] 适配 `ScriptSegment` 新字段 (voiceSampleURL, emotionTag) (Phase 3 已完成)

### Phase 5: 清理 ✅ (已完成)
- [x] 删 `VoiceCatalog.swift` (仍保留, Azure 音色目录用于角色推荐系统; 后续再决定是否移除)
- [x] 删 `VoiceFineTuneView.swift` (已删除)
- [x] 删 `TTSServerListView.swift` (已删除)
- [x] 删 `TemplateManageView.swift`, `TagManageView.swift`, `DefaultTemplates.swift`
- [x] 删 `TTSServer`, `VoiceProfileTuning`, `TagPreset`, `TagCategory`, `RoleTemplate`, `TemplateRole`, `TemplateExport`, `TTSExport` (Models.swift)
- [x] 删 `ttsServers`/`voiceProfiles`/`tagPresets`/`roleTemplates` properties + all CRUD methods (Store.swift)
- [x] 删 `apiEndpoint`/`apiKey` from `ReaderState` (Models.swift) + `Store.swift` + `SettingsView.swift`
- [x] 删 `activeServer` guard in `ReaderView.swift` (CosyVoice 无需服务器配置)

## 数据模型变更

### CharacterProfile (Models.swift)
```swift
var voiceSampleURL: URL?  // 新增: 用于 CosyVoice voice cloning 的参考音频
var voiceSampleEmbedding: Data?  // 新增: 缓存的 CAM++ 192-dim 嵌入
```

### ScriptSegment (Models.swift)
```swift
var emotionTag: String?  // 新增: CosyVoice 情绪标签, 如 "angry"/"sad"/"happy"
var paragraphIndex: Int?  // 新增: 段落索引, 用于朗读高亮同步
```

### TTSQueueItem (Models.swift)
```swift
var paragraphIndex: Int?  // 新增: 段落索引, 用于精确高亮
```

### 删除的模型
- `TTSServer` — 不再需要 HTTP TTS 服务器
- `VoiceProfileTuning` — 不再需要 Azure 音色微调
- `TagPreset` — 不再需要
- `RoleTemplate` — 不再需要
- `VoiceItem` / `VoiceCatalog` — 不再需要 Azure 音色目录

## CosyVoice TTS API 设计

```swift
// CosyVoiceService.swift
actor CosyVoiceService {
    static let shared = CosyVoiceService()
    
    /// 确保模型已下载并初始化
    func ensureModel() async throws
    
    /// 合成多角色对话 (URL-based speaker enrollment)
    func synthesizeDialogue(
        segments: [(speaker: String, text: String, emotion: String?)],
        speakerSamples: [String: URL]
    ) async throws -> Data
    
    /// 合成多角色对话 (pre-computed embeddings + URL fallback)
    func synthesizeDialogueWithEmbeddings(
        segments: [(speaker: String, text: String, emotion: String?)],
        speakerEmbeddings: [String: [Float]],  // cached CAM++ 192-dim
        speakerSamples: [String: URL]          // fallback URLs
    ) async throws -> Data
    
    /// 给角色设定声纹 (CAM++ 提取)
    func enrollSpeaker(name: String, audioURL: URL) async throws -> [Float]
    
    /// 取消正在进行的下载
    func cancelDownload()
    
    /// 从本地导入模型 (文件夹 or .tar.gz)
    func importModel(from sourceURL: URL) async throws
    
    /// 重置下载状态并删除缓存模型
    func resetDownload()
}
```

## 已知问题 & 待优化清单 (2026-07-06 审计)

### P0 — 编译 & 崩溃 (全部已修复 ✅)

| # | 问题 | 状态 |
|---|------|------|
| #30 | CosyVoiceService 多线程下载编译失败 | ✅ 已修复 (改用 withThrowingTaskGroup) |
| #31 | URLSession.AsyncBytes 返回 UInt8 非 Data | ✅ 已修复 (改用 download(for:) streaming) |
| #32 | Data.gunzipped() 在 Xcode 26.3 不可用 | ✅ 已修复 (gunzippedFallback) |
| #33 | tar 提取 size 作用域逃逸 | ✅ 已修复 |
| #BTN | Button("", role:, systemImage:) 参数顺序错误 (Xcode 26.6) | ✅ 已修复 (systemImage 必须在 role 前) |

### P1 — 功能修复 (2026-07-06)

| # | 问题 | 位置 | 状态 |
|---|------|------|------|
| #34 | 模型已下载后无删除按钮 | `TTSView.swift:203` | ✅ 已修复 |
| #35 | 朗读高亮与播放不同步 | `Store.swift:1318` `ReaderView.swift:449` | ✅ 已修复 (使用 paragraphIndex 精确索引) |
| #36 | ScriptSegment/TTSQueueItem 缺少段落索引 | `Models.swift` | ✅ 已修复 (新增 paragraphIndex) |
| #37 | 不能从指定段落开始朗读 | `Store.swift:1291-1296` | ⚠️ fromParagraph 仍用文本匹配 (可通过 paragraphIndex 改进) |
| #38 | 每个 block 合成一个 WAV | `Store.swift:1349-1370` | ⚠️ 仍需优化: 逐句合成可支持逐句跳过 |
| #39 | 播放队列只有 1 个 item | `Store.swift:1370` | ⚠️ 仍需优化: 多 block 连续队列 |
| #40 | 连续合成效率低 | `Store.swift:1373-1381` | ⚠️ 仍需优化: 用 checkedContinuation 等播完再合成 |
| #41 | 格式化文本未替换原文件 | `Store.swift:740-748` | ⚠️ 实际已替换但 UI 不明显 |
| #EMB | playChapterStreaming 未使用缓存的 voiceSampleEmbedding | `Store.swift:1305-1309` | ✅ 已修复 (新增 synthesizeDialogueWithEmbeddings) |

### P1 — 下载 & 导入

| # | 问题 | 位置 | 状态 |
|---|------|------|------|
| #DL1 | 下载使用 Data(count:) 预分配 1GB 内存 | `CosyVoiceService.swift:335` | ✅ 已修复 (改用 download(for:) streaming) |
| #DL2 | 多线程 Range 下载通过代理可能失败 | `CosyVoiceService.swift` | ✅ 已修复 (简化为单线程 download(for:)) |
| #DL3 | 文件导入器不能选取 .tar.gz 文件 | `TTSView.swift:272` | ✅ 已修复 (使用 UTType(filenameExtension:"tar.gz")) |
| #DL4 | 导入 .tar.gz 后的安全访问权限跨异步边界 | `TTSView.swift` | ✅ 已修复 (bookmark + startAccessingSecurityScopedResource) |
| #DL5 | importModel 路径硬编码 HF cache | `CosyVoiceService.swift:475` | ⚠️ HuggingFaceDownloader.getCacheDirectory 与新下载目录不一致 |
| #DL6 | downloadProgress 的 refreshStatus 竞态 | `TTSView.swift:358-364` | ✅ 已修复 (refreshStatus 不覆盖用户触发的 .downloading) |
| #DL7 | 下载无取消/继续按钮 | `TTSView.swift` | ✅ 已修复 (新增 cancelDownload + 取消按钮) |
| #DL8 | 下载进度只显示 0.5→1.0，无百分比/速度 | `CosyVoiceService.swift:322` | ⚠️ download(for:) 不提供中间进度, 仅显示 spinning + 取消按钮 |

### P2 — 逻辑缺陷

| # | 问题 | 位置 | 状态 |
|---|------|------|------|
| #42 | 同本书扫描角色多次重复累积 | `CharacterAssignmentView.swift` `Store.swift` | ✅ 已修复 (scanCharacters 先 removeAll 当前书) |
| #43 | 缓存音频无清理机制 | `CosyVoiceService.swift:58-66` | ⚠️ evictDiskLRU 已实现但未充分测试 |
| #44 | BERT speaker detection 未做错误处理 | `BertSpeakerDetector.swift` | ⚠️ 仍待修复 |
| #45 | ReaderView 滚动到朗读段不可靠 | `ReaderView.swift:1194` | ✅ 间接修复 (paragraphIndex 改善匹配准确度) |
| #46 | 语音测试可能播放过期缓存 | `TTSView.swift:testSection` | ⚠️ 仍待修复 |
| #47 | dispatchWorkItem 取消防抖竞态 | `ReaderView.swift` | ⚠️ 仍待修复 |
| #48 | Logger 日志文件不轮转 | `Logger.swift` | ⚠️ 仍待修复 |
| #49 | createScriptSegments 每次创建新 CharacterAnalyzer | `Store.swift:1562` | ✅ 已修复 (复用单例) |

### P2 — 新增审计发现 (2026-07-06)

| # | 问题 | 位置 | 描述 |
|---|------|------|------|
| #50 | **VoiceCatalog/VoiceItem 混淆** | `Models.swift` `Store.swift` | CosyVoice 使用 CAM++ 嵌入而非 Azure 音色 ID; VoiceCatalog 音色推荐机制对 CosyVoice 无效, 但 UI 仍然显示 Azure 音色选择器 |
| #51 | **createScriptSegments 创建大量 non-bookID 角色** | `Store.swift:1565` | `speakerProfile == nil` 时创建临时 CharacterProfile, 设置 voice 为 Azure ID (对 CosyVoice 无意义) |
| #52 | **playChapterStreaming 每个 block 只高亮第一段** | `Store.swift:1318` | `currentParagraphIndex = block.globalStart` 仅指向 block 起始段, block 内 3-5 个段落播放期间高亮不更新 (待 #38 分句合成后修复) |
| #53 | **synthesizeDialogue 缓存键不含段落文本** | `CosyVoiceService.swift:503` | cacheKey 只含 dialogue segments, 不含段落索引 — 同一对话在同章出现多次时返回错误缓存 |
| #54 | **downloadAndExtract 无进度中间态** | `CosyVoiceService.swift:322` | `reportProgress(0.5)` 设 50%, download(for:) 完成后设 100%。用户看不到实际下载进度。 |
| #55 | **DedupByName 在两个位置实现不一致** | `Store.swift` vs `CharacterAssignmentView.swift` | Store.scanCharacters 使用 CharacterScanner.scan 内置 dedup; CharacterAssignmentView.startScan 手工实现 4 阶段 dedup。行为可能不一致。 |
| #56 | **Book.text 空但文件存在时需重新读取** | `ReaderView.swift:1113-1137` | `ensureChaptersLoaded` 在 `book.text.isEmpty` 时从文件系统读取, 但读取后不更新 `book.text` 字段, 下次仍需重读。 |

## 修复记录 (2026-07-06)

| 提交 | 描述 |
|------|------|
| `c92a0d8` | fix: Button parameter order for Xcode 26.6 |
| `456b080` | fix: singleDownload byte-by-byte + memory + picker + timer race |
| `1c82e7c` | fix: Data(count:) OOM + file picker .gzip->.data + timer race |
| `725368e` | fix: simplify download + cancel support + file picker .tar.gz |
| `db2228c` | fix: highlight sync + embeddings + dedup + perf |

## 下一步 (优先级排序)

1. **P0: 文件导入器仍然不能选取 .tar.gz** — 需要用户再次测试, 确认 `UTType(filenameExtension:"tar.gz")` 在 iOS 18 上是否有效; 若无效则使用 `.data` 兜底
2. **P1: 下载进度显示** — download(for:) 不提供中间进度, 需要 URLSessionDataDelegate 实现流式进度
3. **P1: 逐句合成 + 连续队列** — 拆分 block 为单句合成, 队列支持多 block 连续播放
4. **P2: VoiceCatalog 清理** — 移除 Azure 音色目录/推荐, 替换为 CosyVoice 角色→嵌入→音色映射
