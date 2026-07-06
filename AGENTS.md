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

## 注意事项

1. CosyVoice 3 需要 iOS 18+ (MLState API) ✅ 已满足
2. 首次运行需要从 HuggingFace 下载 ~1.5GB 模型 (4-bit)
3. 用 `--cosyvoice-variant 4bit` 减少内存占用
4. 无参考音频的角色用内置默认音色
5. 情绪标签可选, 不传则 CosyVoice 自动根据文本调语气
