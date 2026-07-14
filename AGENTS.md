# FeatureTTSReader — 多角色 TTS 朗读器

## 当前架构（2026-07-14）

```
iOS 18+ / Swift 6 / SwiftUI / Xcode 26.6

角色提取
  └─ [已废弃 CharacterScanner] → AI Worker (Cloudflare Workers AI, qwen-2.5-7b-instruct)
  └─ AIWorkerService.processChapter 切片 → 逐片 POST → 合并 AISegment 数组

AI Worker 接口
  └─ POST 到用户部署的 Cloudflare Worker URL
  └─ Header: X-Auth-Key (鉴权)
  └─ Body: {"text": "...", "slice_index": N, "total_slices": N, "context": ...}
  └─ 返回: JSON array [{speaker, emotion, tone, text}] 或 AIWorkerResult {segments, nextContext}
  └─ 重试: 结果截断时最多重试 2 次（最后一段以标点结尾 + 段落数≥2 时触发）

TTS 引擎 (Edge TTS)
  └─ HTTP GET → Edge TTS 服务器 → WAV/MP3 音频数据
  └─ SSML emotionTag: sad/angry/cheerful/neutral (基于 AI Worker 返回的 emotion)
  └─ rate/pitch: 角色级配置 (±0~50%)
  └─ volume: tone→volume 映射 + 全局音量叠加

播放管线（TTSView 流式）
  processCustomWithWorker()
    → sliceText → 逐片 sendRequest → AISegment[]
    → mergeConsecutiveSegments() (合并相同说话人/情绪/语气的连续段落)
    → 首片 assignVoicesToSegments() 分配音色
    → 并发 withThrowingTaskGroup + SynthesisBuffer 保序合成
    → appendToQueue → playNextSeamlessly → AVAudioPlayer 逐个播放

播放管线（ReaderView·书籍朗读，待替换）
  playChapterStreaming
    → 逐段 → 逐句 splitBlockIntoSentences
    → parseDialogueSegments (引号匹配+正则说话者检测)
    → DramaDirector.contextualize (上下文情绪平滑)
    → AudioPrefetcher (滑动窗口 5 并发预取)
    → 每句 1 TTSQueueItem → AdvancedAudioPlaybackController.playQueue/appendToQueue
    → AVAudioPlayer 逐个播放 → delegate 驱动下一句

调试日志 DebugLogger
  └─ Documents/debug/debug_yyyMMdd_HHmmss.jsonl (每启动一个文件)
  └─ 每行一个 JSON 对象 → flow/step/details
  └─ 覆盖: AI Worker 请求/响应, Edge TTS 请求/响应, 多角色编排, 播放时间线
```

## 核心功能支柱

### 1. AI 剧本解析 Worker 配置 (`TTSView.aiWorkerSection`)
- **Worker 列表**：每个 worker 显示名称、URL、状态圆点（绿/黄/灰/红）、默认标记
- **上下文菜单**：编辑／测试连接／设为默认／删除
- **WorkerEditView**：名称、Base URL、Auth Key（模型固定为 qwen-2.5-7b-instruct）、切片字符限制、超时
- **状态检测**：`workerStatuses[UUID]` 字典，通过 `statusDot` 显示颜色
- **持久化**：`loadWorkerConfigs()` / `saveWorkerConfigs()` → UserDefaults

### 2. 自定义多角色测试 (`TTSView.customMultiRoleSection`)
- **文本输入** → **「AI 解析并流式播放」** → `processCustomWithWorker()` (一站式)
  - 循环每片: `AIWorkerService.sliceText()` + `sendRequest()` → 分段
  - 首片时自动分配音色 `assignVoicesToSegments()` (显示 Picker 供实时覆盖)
  - `mergeConsecutiveSegments()` 合并同角色连续段落
  - 并发 `withThrowingTaskGroup` 合成 + `SynthesisBuffer` 保序
  - 首段 `appendToQueue` 触发播放，后续批量 `appendToQueue(restItems)`
- **「重播」** → `synthesizeAndPlayCustom()`（复用已解析的 `customWorkerSegments`）
- **全局语速滑块**：`-10~10`，叠加到每个角色的基础语速
- **全局音量滑块**：`-12~12 dB`，叠加到每段的 resolvedVolume
- **全局重叠滑块**：`0~500ms`，通过 `play(atTime:)` 实现无缝切换

### 3. VoicePickerPopover（TTSView 底部）
- 通用的音色选择弹出菜单，使用 `List` 替代 `Menu` 突破 HStack 限制
- 每行显示 `shortVoiceLabel`（中文名/英文短名:模型后缀）+ 性别徽章（♂/♀）
- 顶部「自动」选项，选中行显示 checkmark

### 4. 角色管理（TTSView 内联）
- **CharacterRoleCard**：显示角色名、性别徽章、当前音色、情绪摘要
- **音色选择器**：popover 方式弹出 VoicePickerPopover
- **上下文菜单**：合并(alias)、分离(alias→独立角色)、改名、删除
- **别名系统**：`characterAliases: [String: String]` (别名→主名)，合并时设别名不分段改名

### 5. 书籍朗读界面（ReaderView，待整合多角色模块）
- **文本渲染**：LazyVStack 按段落滚动，`scrollPositionID` 纯段落 ID 定位
- **高亮同步**：基于 `PlaybackAnchor` + `store.currentParagraphIndex`/`currentSentenceIndex`
- **朗读控制**：底部栏含章节滑块、播放状态、句子级跳转（上/下一句、上/下一段）
- **角色面板**：sheet 中扫描+分配+角色列表（功能弱于 TTSView）

## 数据流细节

```
自定义多角色文本
  → processCustomWithWorker() [一站式流式]
    切片 [sliceText]
    ↓
    第 0 片: sendRequest → AI Worker → [AISegment]
      → assignVoicesToSegments() 首次分配音色
      → mergeConsecutiveSegments() 合并同角色连续段落
      → 并发 withThrowingTaskGroup 合成 + SynthesisBuffer 保序
      → 首段: appendToQueue → playNextSeamlessly → 开始播放
      → 剩余段: appendToQueue(restItems)
    ↓
    第 1 片: sendRequest → AI Worker → [AISegment]
      → 合并 + 并发合成 → appendToQueue(restItems)
    ↓ ...
    → AVAudioPlayer delegate 驱动后续播放

书籍章节（ReaderView，待替换）
  当前: 扫描角色 → 本地脚本生成 → 逐句合成
  目标: 扫描角色 → AI 逐片解析 → 并发合成 → 保流入队
```

## 调试日志 DebugLogger

- **位置**：`DebugLogger.swift`，`FeatureTTSReaderApp.swift` 中 `.task { DebugLogger.startSession() }` 启动
- **输出**：`Documents/debug/debug_20260712_143022.jsonl`（每启动一个文件）
- **格式**：JSON Lines，每行一个 JSON 对象
  ```json
  {"timestamp":"...","flow":"ai_worker","step":"sendRequest_outgoing","details":{...}}
  {"timestamp":"...","flow":"edge_tts","step":"synthesize_response","details":{...}}
  ```
- **覆盖流程**：
  - `session.start` — app 启动
  - `ai_worker.processChapter_start/end` — 原文长度、切片数、合并后分段数
  - `ai_worker.sendRequest_outgoing/response/decoded/error` — 请求/响应/状态码/分段预览
  - `ai_worker.parse_retry` — 截断结果重试次数
  - `edge_tts.synthesize_start/request/response/error` — text/voice/rate/pitch/HTTP status/data长度
  - `custom_multi_role.processCustomWithWorker_*` — 编排上下文
  - `custom_synthesize.start/first_segment_error/remaining_segment_error/complete` — 合成进度
  - `segment_schedule` / `segment_start` / `segment_finish` / `segment_switch` — 播放时间线

### Emotion 映射（worker.js → Swift → Edge TTS）

| worker.js | Swift Emotion | Edge TTS style |
|-----------|---------------|----------------|
| `neutral` | `.neutral` | `neutral` |
| `happy` | `.happy` | `happy` |
| `excited` | `.excited` | `excited` |
| `angry` | `.angry` | `angry` |
| `sad` | `.sad` | `sad` |
| `fear` | `.fearful` | `fearful` |
| `whisper` | `.whispering` | `whispering` |
| `cheerful` | `.cheerful` | `cheerful` |
| `surprised` | `.surprised` | `surprised` |
| `disgusted` | `.disgusted` | `disgusted` |
| `calm` | `.calm` | `calm` |
| 其他 | `.neutral`(默认) | `neutral`(默认) |

### EdgeVoiceInfo 标准化

- `baseVoiceID(_:)` — 剥离 `:.*` 后缀和 `"Neural"` 尾缀（如 `zh-CN-Xiaoxiao:DragonHDFlashLatestNeural` → `zh-CN-Xiaoxiao`）
- `chineseVoiceName(for:)` — 拼音→中文映射（键不含 "Neural" 后缀）
- `shortVoiceLabel(_:name:)` — 格式：`晓晓/Xiaoxiao:DragonHD`
- `shortModelSuffix(_:)` — 剥离常见后缀（`FlashLatestNeural`、`LatestNeural` 等）
- `EdgeVoiceInfo.displayName` — 本地化中文名 + gender 图标

## 关键决策

- ❌ **否决 CosyVoice 3 / CAM++ / BERT / MLX** — 改为 Edge TTS HTTP API
- ❌ **否决 AVAudioEngine** — 改为 AVAudioPlayer（规避 LiveContainer 音频 entitlements 崩溃）
- ❌ **否决像素偏移滚动** — 改为 `scrollPositionID` 纯段落 ID 定位
- ❌ **否决 CharacterScanner** — 改为 Cloudflare Workers AI
- ✅ **AI Worker 模型固定** — qwen-2.5-7b-instruct，不在客户端配置
- ✅ **DebugLogger .jsonl 格式** — 每启动一个文件，行追加，方便整体发送
- ✅ **Worker 状态检测** — context menu「测试连接」+ 状态圆点
- ✅ **别名系统** — `characterAliases: [String: String]` (别名→主名)，合并时设别名不分段改名；`voiceForSpeaker` 别名自动继承主角色音色；ContextMenu 分离别名
- ✅ **推荐音色名** — 中文名(小晓)作为主显，英文ID小字在下行
- ✅ **VoicePickerPopover** — List 替代 Menu，突破 HStack 限制，支持 gender badge
- ✅ **SynthesisBuffer** — actor 保序，并发合成后按 idx 顺序入队
- ✅ **mergeConsecutiveSegments** — 合并相同 speaker/emotion/tone 的连续段落
- ✅ **safeOverlap** — `min(overlapMs/1000, current.duration/2)` 防止重叠超出音频时长
- ✅ **AI Worker 重试** — 截断结果时最多重试 2 次带上下文

## 构建方式

- 本开发环境（Linux）**无 Xcode**，`xcodebuild` 不可用
- 每次修改后 `git push` → GitHub Actions CI 自动编译
- 通过 `gh run list` / `gh run watch` 查看编译结果
- 本地验证仅靠 `git diff`、`swift-format --lint` 等非编译检查

## iOS 18+ / Xcode 26.6 注意事项

- `Button("", systemImage:, role:)` — systemImage 必须在 role 前
- `onChange(of:)` — 需双参数 `{ oldValue, newValue in }`
- `ForEach` inside `@ViewBuilder` — 用 `Array(0..<count)` 显式化
- `@ViewBuilder` 内 `var` + `if` 变异会被解释为条件视图构建 → 用 `let` + 三元
- `OSAllocatedUnfairLock` — `import os` 后可用
- `DateFormatter` 是 Sendable-safe（Swift 6），`ISO8601DateFormatter` 不是
- `xcodebuild` 当前环境不可用（Linux）— 验证必须通过 GitHub Actions CI: `gh run list` / `gh run watch`

## 修复记录 (2026-07-12)

| 提交 | 描述 |
|------|------|
| `bf8eace` | **feat: DebugLogger 时间戳文件日志 (Worker/TTS 数据流)** |
| `84f7897` | **fix: Sendable conformance — 避免 closure 捕获非 Sendable 类型** |
| `87acb02` | **fix: worker.js 响应格式兼容 + Emotion 自定义 Codable** |
| `f0cb98b` | **fix: Emotion.rawValue 补全 + WorkerEditView 模型字段移除** |
| `1e496f8` | **fix: Picker 闭合括号修复 struct 层级** |
| `9dd7ede` | **fix: 删除冗余 CharacterAnalyzer 合成块, synthesizeSSML→synthesize** |
| `9ecd6d1` | **fix: 添加 Worker 编辑/状态检测 UI** |
| `ac5daca` | **fix: iOS 端 JSON 响应兜底修复 — 自动转义 LLM 返回中 text 字段未转义的双引号** |
| `643ef6a` | **fix: 播放重复 — 按钮未禁用(isProcessing→isSynthesizing) + 预加载路径队列不移除** |
| `3056022` | **feat: 分片流式合成 — 每片 AI 解析后立即合成入队播放 (合并为单按钮)** |

| 提交 | 描述 |
|------|------|
| `cd85e68` | **P0: embedding格式/称呼语方向/cancelDownload/stop/resume/bookID/情绪分析/数据竞争** |
| `62300cd` | **P0: AVAudioEngine→AVAudioPlayer 重写（修复LiveContainer崩溃）** |
| `f9287f0` | **P0: 纯段落ID定位，删除全部像素估算代码** |
| `1965409~c5975eb` | TTS批修复 (1-8) |

## 修复记录 (2026-07-13)

| 提交 | 描述 |
|------|------|
| `57aa236` | **perf: health check 改用 /api/v1/tts (更快)** |
| `afd0f95` | **feat: 拆分解析/播放按钮 + AI 性别检测 (AISegment.gender / worker.js gender)** |
| `26d0bb7` | **feat: tone→volume 映射, SSML volume 支持 (vol 查询参数 / buildSSML prosody volume)** |
| `e8dc97f` | **feat: 全局音量滑块 + Settings 页同步 (resolvedVolume dB叠加)** |
| `cfd86f8` | **fix: 流式逐段入队 / 角色卡不消失 / 刷新自动匹配音色 / 稳定播放控制** |

## 修复记录 (2026-07-14)

| 提交 | 描述 |
|------|------|
| `250e30c` | **ui: fix voice picker popover (state at struct level, list with gender badges)** |
| `9d5f693` | **fix: remove duplicate declarations, fix voice picker popover** |

## 当前已知问题

1. **worker.js 偶尔空响应** — LLM 复杂场景下返回空, 已添加基础 prompt 降级重试 (需重新部署 `temp/worker.js`)
2. **config voices 为空** — 服务器 `/api/v1/config` 返回 empty voices 列表, 但已添加 `defaultChineseVoices` 兜底, 不影响音色匹配
3. **性别检测准确率** — 取决于 LLM 对角色的理解, `unknown` 时回退名字关键词

## 下一步计划

### 书籍朗读界面整合多角色 TTS 模块

详见 `Docs/book-reader-integration-plan.md`

核心变更：
1. 抽取通用组件：`CharacterRoleCard`、`VoicePickerPopover`、`SynthesisBuffer` 为独立文件
2. 替换 `playChapterStreaming()` → 使用 AI Worker 按片解析 + 并发合成 + 保序入队
3. 角色面板改用 CharacterRoleCard + 别名系统
4. 底部控制栏增加语速/音量/重叠滑块
5. ReaderSettingsView 增加朗读设置 Section
6. 保留本地解析模式作为回退
