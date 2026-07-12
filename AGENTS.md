# FeatureTTSReader — 多角色 TTS 朗读器

## 当前架构（2026-07-11）

```
iOS 18+ / Swift 6 / SwiftUI / Xcode 26.6

角色提取 (CharacterScanner)
  └─ extractCandidates (正则+NLTagger) → countCharacterFrequencies (AC自动机) → estimateAttributes (全局投票)

TTS 引擎 (Edge TTS)
  └─ HTTP GET → Edge TTS 服务器 → WAV/MP3 音频数据
  └─ SSML emotionTag: sad/angry/cheerful/neutral (基于文本情绪分析)
  └─ rate/pitch: 角色级配置 (±0~50%)

播放管线
  playChapterStreaming
    → 逐段 → 逐句 splitBlockIntoSentences
    → parseDialogueSegments (引号匹配+正则说话者检测)
    → DramaDirector.contextualize (上下文情绪平滑)
    → AudioPrefetcher (滑动窗口 5 并发预取)
    → 每句 1 TTSQueueItem → AdvancedAudioPlaybackController.playQueue/appendToQueue
    → AVAudioPlayer 逐个播放 → delegate 驱动下一句
```

## 核心功能支柱

### 1. 多角色测试模块 (`TTSView.multiRoleTestSection`)
- **位置**：TTS 设置页 → 「多角色测试」区块
- **预置 9 段对话**：旁白×5、云希(愤怒)、云健(沉稳)、晓北(调侃)、陕兵(恐惧) —— 各自固定音色/语速/音调/台词
- **全局语速滑块**：`-10~10`，**叠加**到每个角色自带语速上（角色 +3，全局 +2 → 实际 +5）
- **真流水线播放**：
  1. 首段合成 → 写文件 → `appendToQueue([first])` → **立即开播**
  2. 后台并行合成剩余段 → 收集 `restItems`
  3. 全部合成完 → `appendToQueue(restItems)` 一次性入队
  4. `AVAudioPlayer` delegate 依次播完，无竞态
- **实时进度**：`第 1 段合成完成，开始播放...` → `第 1 段播放中，后续合成中...` → `9/9 段全部入队，正在流式播放`
- **暂停/继续按钮**：播放时显示暂停图标，暂停后显示继续图标，调用 `AdvancedAudioPlaybackController.pause()` / `resume()`，队列位置不变

### 2. 全局语速叠加控制
- **作用**：用户可在多角色测试页拖动「全局语速」滑块，数值**加法叠加**到每个角色的基础语速
- **实现**：`combinedRate = scene.rate + multiRoleGlobalRate`，传给 `EdgeTTSService.synthesize(rate:)`
- **意义**：无需逐个改角色参数，一键整体加快/放慢整场对话节奏

## 关键决策

- ❌ **否决 CosyVoice 3 / CAM++ / BERT / MLX** — 改为 Edge TTS HTTP API
- ❌ **否决 AVAudioEngine** — 改为 AVAudioPlayer（规避 LiveContainer 音频 entitlements 崩溃）
- ❌ **否决像素偏移滚动** — 改为 `scrollPositionID` 纯段落 ID 定位（`ch_N_p_M`）
- ✅ **每个 sentence 独立 TTSQueueItem** — 支持逐句跳过
- ✅ **DramaDirector** — 叙述者情绪继承 + 连续说话者平滑 + 高潮预判
- ✅ **Edge TTS 音色策略** — 固定用 zh-CN-XiaoxiaoNeural(女)/YunxiNeural(男) 等少量音色，通过 rate/pitch/style 参数化演绎不同性格角色，无需大量音色库
- ✅ **角色-音色分配 UI** — 在书籍详情页和朗读页中提供手动分配 Edge TTS 音色给角色的界面
- ✅ **CharacterEditorView** — 仅保留名称/性别/年龄/语气字段，音色由 Edge TTS 自动分配

## 数据流细节

```
book_text → parseDialogueSegments → [DialoguePart(speaker, text, emotionTag)]
  → 别名→规范名映射 → SentenceUnit → DramaDirector.contextualize
  → EdgeTTSService.synthesize → AudioPrefetcher 缓存
  → TTSQueueItem(segment, audioData, anchor)
  → queue.append → playNextSeamlessly → AVAudioPlayer.play
  → audioPlayerDidFinishPlaying → playNextSeamlessly (delegate 自驱)
```

## F1/F2/F3 已实现状态

| Feature | 实现 | 状态 |
|---------|------|------|
| **F1** fromParagraph | `playChapterStreaming(fromParagraphIndex:fromSentenceIndex:)` → `skipToSegment()` | ✅ |
| **F2** 逐句跳过 | `skipCurrentSentence/Paragraph`, `skipPreviousSentence/Paragraph`, `skipForward/Backward` | ✅ |
| **F3** 预加载队列 | `AudioPrefetcher` 5窗口滑动并发 → `appendToQueue` 流式追加 | ✅ |

## 构建方式

- 本开发环境（Linux）**无 Xcode**，`xcodebuild` 不可用
- 每次修改后 `git push` → GitHub Actions CI 自动编译
- 通过 `gh run list` / `gh run watch` 查看编译结果
- 本地验证仅靠 `git diff`、`swift-format --lint` 等非编译检查

## 已知待优化（非阻断）

- 区域点击翻页仍用像素偏移（可改为段落级跳转）
- `cachedParagraphs` 切换书籍时未清理
- BERTSpeakerDetector.swift 有未使用的 try-catch 包装
- 锁屏 MPRemoteCommandCenter 需真机验证

## iOS 18+ / Xcode 26.6 注意事项

- `Button("", systemImage:, role:)` — systemImage 必须在 role 前
- `onChange(of:)` — 需双参数 `{ oldValue, newValue in }`
- `ForEach` inside `@ViewBuilder` — 用 `Array(0..<count)` 显式化
- `@ViewBuilder` 内 `var` + `if` 变异会被解释为条件视图构建 → 用 `let` + 三元
- `OSAllocatedUnfairLock` — `import os` 后可用
- `xcodebuild` 当前环境不可用（Linux）— 验证必须通过 GitHub Actions CI: `gh run list` / `gh run watch`

## 修复记录 (2026-07-11 最终批)

| 提交 | 描述 |
|------|------|
| `cd85e68` | **P0: embedding格式/称呼语方向/cancelDownload/stop/resume/bookID/情绪分析/数据竞争** |
| `62300cd` | **P0: AVAudioEngine→AVAudioPlayer 重写（修复LiveContainer崩溃）** |
| `f9287f0` | **P0: 纯段落ID定位，删除全部像素估算代码** |
| `1965409` | TTS批1: 死代码/SSML前缀/URL/isBusy |
| `8e2644d` | TTS批2: playbackContinuation/skipBackward/TTSView竞态 |
| `9218bb6` | TTS批3: isPlaying/称呼语方向 |
| `c186b63` | TTS批4: DramaDirector 3条 |
| `fab4312` | TTS批4续: AudioPrefetcher超时 |
| `9e90b7c` | TTS批5: defaultVoice/voiceMatchScore |
| `6f74635` | TTS批6+7: CharacterEditorView + AVAudioPlayerController |
| `2afee96` | TTS批8: T1a pIdx + T1d ScriptSegment metadata |
| `c5975eb` | TTSView: hasPrefix/API key mask/stale status/URL params |
