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
    
    /// 合成多角色对话
    func synthesizeDialogue(
        segments: [(speaker: String, text: String, emotion: String?)],
        speakerSamples: [String: URL]  // 角色名 → 参考音频路径
    ) -> AsyncThrowingStream<Data, Error>
    
    /// 给角色设定声纹 (CAM++ 提取)
    func enrollSpeaker(name: String, audioURL: URL) async throws -> [Float]
}
```

## 待处理事项 (2026-07-06)

### 全部完成 ✅

| 编号 | 项目 | 状态 | 提交 |
|------|------|------|------|
| #6 | 全屏 TapGesture 冲突 | ✅ 已改为双击 | `8dfec25` |
| #10 | 两套 Scan 逻辑统一 → `CharacterScanner` | ✅ `scanCharacters`/`startScan` 共享核心管线 | `f289e46` |
| #12 | `segmentStartOffset` 同步误触发 | ✅ 0.15s 滞后防抖 | `f289e46` |
| #14-15 | SettingsView/BookshelfView 拆分 | ✅ 5 个子文件 | `9e61667` |
| #26 | 扫描阶段提示文字中文化 | ✅ "正则匹配" → "正在扫描角色..." | `9e61667` |
| #27 | 录制前 audio 时长校验 | ✅ ≥ 3s 检查 | `9e61667` |
| #28 | 章节列表搜索/筛选 | ✅ `.searchable()` 支持 | `9e61667` |

### 启动崩溃 (已修复)
- 根本原因: `CosyVoiceService.prewarm()` → `CosyVoiceTTSModel.fromPretrained()` 内部 fatal (非 throw)
- 修复: 移除 `prewarm()` 调用, 模型在首次用户操作时惰性加载
- 确认: Commit `610d1d9` 经过验证可正常工作

## 已知问题 & 待优化清单 (2026-07-06 审计)

### P0 — 编译 & 崩溃

| # | 问题 | 位置 | 描述 |
|---|------|------|------|
| #30 | CosyVoiceService 多线程下载编译失败 | `CosyVoiceService.swift:359` | `DispatchGroup.wait()` 在 actor 上下文中不可用，改用 `withThrowingTaskGroup` |
| #31 | URLSession.AsyncBytes 返回 UInt8 非 Data | `CosyVoiceService.swift:382` | `for try await data in stream` 中 `data` 是 `UInt8`，需收集到 buffer |
| #32 | Data.gunzipped() 在 Xcode 26.3 不可用 | `CosyVoiceService.swift:408` | iOS 18 Foundation 不包含该方法，统一用 `gunzippedFallback()` |
| #33 | tar 提取 `size` 作用域逃逸 | `CosyVoiceService.swift:434` | else 分支引用了 if-let 内的 `size`，修复为 `fileSize` |

### P1 — 功能缺失

| # | 问题 | 位置 | 描述 |
|---|------|------|------|
| #34 | **模型已下载后无删除按钮** | `TTSView.swift:196` | .ready 状态只显示"已就绪"，无删除选项。已修复 ✅ |
| #35 | **朗读高亮与播放不同步** | `Store.swift:1318` `ReaderView.swift:449` | `currentParagraphIndex` 只在 block 级别更新（每个 block 仅设一次），整个 block 播放期间高亮不随句子变化；高亮依赖文本匹配（`paraText.contains(...)`），同一文本出现两处会错误高亮 |
| #36 | **ScriptSegment 缺少段落索引** | `Models.swift`, `Store.swift` | TTSQueueItem/ScriptSegment 没有记录 `paragraphIndex` 或 `globalStart`，ReaderView 无法精确高亮当前朗读段落 |
| #37 | **不能从指定段落开始朗读** | `Store.swift:1291-1296` | `fromParagraph` 参数通过文本匹配查找起始段，没有精确的段落索引支持 |
| #38 | **每个 block 合成一个 WAV** | `Store.swift:1349-1370` | 整个 block 合并成一个音频，用户无法逐句跳过/暂停，进度只能精确到 block |
| #39 | **播放队列只有 1 个 item** | `Store.swift:1370` | `audioController.playQueue([item])` 每次只放 1 个，不能连续播放多个 block |
| #40 | **连续合成效率低** | `Store.swift:1372-1381` | 用 `withCheckedContinuation` 等一个 block 播完再合成下一个，阻塞了合成管线 |
| #41 | **格式化文本未替换原文件？** | `Store.swift:740-748` | 实际已替换（saveBookTextToFile 保存 normalized 文本），但 `reformatBookText` 没有被 UI 明显暴露 — **用户不知道可以重新格式化** |

### P2 — 逻辑缺陷

| # | 问题 | 位置 | 描述 |
|---|------|------|------|
| #42 | **同本书扫描角色多次会重复累积** | `CharacterAssignmentView.swift` / `Store.swift` | 多次点「扫描角色」会向 `characters` 追加，而不是重置后再扫描 |
| #43 | **缓存音频无清理机制** | `CosyVoiceService.swift:58-66` | `diskCacheQuota = 100MB` 没有实际执行 LRU 驱逐，只计数不删除 |
| #44 | **BERT speaker detection 未做错误处理** | `BertSpeakerDetector.swift` | 如果 Core ML 模型不存在，返回空 embedding 导致余弦相似度计算崩溃 |
| #45 | **importModel 路径硬编码 HF cache** | `CosyVoiceService.swift` | `importModel` 用的 cache 目录是 `HuggingFaceDownloader.getCacheDirectory()`，而现在的下载逻辑不用 HF 了，可能导致不一致 |
| #46 | **ReaderView 滚动到朗读段不可靠** | `ReaderView.swift:212` | `autoScrollOffset(for: currentSegmentText)` 通过文本匹配查找位置，无精确偏移 |
| #47 | **语音测试可能播放过期缓存** | `TTSView.swift:testSection` | `store.ttsTestAudioURL` 可能指向已删除的文件 |
| #48 | **dispatchWorkItem 取消防抖竞态** | `ReaderView.swift` | `segmentStartOffset` 防抖中使用 `dispatchWorkItem?.cancel()`，但 dispatch 到 main 后有延迟，可能仍会执行 |
| #49 | **Logger 日志文件不轮转** | `Logger.swift` | 1MB 限制只检查一次，日志文件持续增长 |

1. CosyVoice 3 需要 iOS 18+ (MLState API) ✅ 已满足
2. 首次运行需要从 HuggingFace 下载 ~1.5GB 模型 (4-bit)
3. 用 `--cosyvoice-variant 4bit` 减少内存占用
4. 无参考音频的角色用内置默认音色
5. 情绪标签可选, 不传则 CosyVoice 自动根据文本调语气
