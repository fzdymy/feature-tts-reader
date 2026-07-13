# FeatureTTSReader — 多角色 TTS 朗读器

## 当前架构（2026-07-12）

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

TTS 引擎 (Edge TTS)
  └─ HTTP GET → Edge TTS 服务器 → WAV/MP3 音频数据
  └─ SSML emotionTag: sad/angry/cheerful/neutral (基于 AI Worker 返回的 emotion)
  └─ rate/pitch: 角色级配置 (±0~50%)

播放管线
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
  └─ 覆盖: AI Worker 请求/响应, Edge TTS 请求/响应, 多角色编排
```

## 核心功能支柱

### 1. AI 剧本解析 Worker 配置 (`TTSView.aiWorkerSection`)
- **Worker 列表**：每个 worker 显示名称、URL、状态圆点（绿/黄/灰/红）、默认标记
- **上下文菜单**：编辑／测试连接／设为默认／删除
- **WorkerEditView**：名称、Base URL、Auth Key（模型固定为 qwen-2.5-7b-instruct）、切片字符限制、超时
- **状态检测**：`workerStatuses[UUID]` 字典，通过 `statusDot` 显示颜色
- **持久化**：`loadWorkerConfigs()` / `saveWorkerConfigs()` → UserDefaults

### 2. 自定义多角色测试 (`TTSView.customMultiRoleSection`)
- **文本输入** → **「AI 解析并流式播放」** → `processCustomWithWorker()` (已合并)
  - 循环每片: `AIWorkerService.sliceText()` + `sendRequest()` → 分段
  - 首片时自动分配音色 `assignVoicesToSegments()` (显示 Picker 供实时覆盖)
  - 逐段 `EdgeTTSService.synthesize()` → 首段立即 `appendToQueue` 触发播放
  - 后续段批量 `appendToQueue(restItems)` 追加到队列尾部
- **「重播」** → `synthesizeAndPlayCustom()`（复用已解析的 `customWorkerSegments`）
- **全局语速滑块**：`-10~10`，叠加到每个角色的基础语速
- **暂停/继续按钮**

## 数据流细节

```
自定义多角色文本
  → processCustomWithWorker() [一站式流式]
    切片 [sliceText]
    ↓
    第 0 片: sendRequest → AI Worker → [AISegment]
      → assignVoicesToSegments() 首次分配音色
      → 逐段: EdgeTTSService.synthesize() → 写文件
      → 首段: appendToQueue → playNextSeamlessly → 开始播放
      → 剩余段: collect restItems → appendToQueue(restItems)
    ↓
    第 1 片: sendRequest → AI Worker → [AISegment]
      → 逐段 synthesize → collect restItems → appendToQueue(restItems)
    ↓ ...
    → AVAudioPlayer delegate 驱动后续播放
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
  - `edge_tts.synthesize_start/request/response/error` — text/voice/rate/pitch/HTTP status/data长度
  - `custom_multi_role.processCustomWithWorker_*` — 编排上下文
  - `custom_synthesize.start/first_segment_error/remaining_segment_error/complete` — 合成进度

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

## 关键决策

- ❌ **否决 CosyVoice 3 / CAM++ / BERT / MLX** — 改为 Edge TTS HTTP API
- ❌ **否决 AVAudioEngine** — 改为 AVAudioPlayer（规避 LiveContainer 音频 entitlements 崩溃）
- ❌ **否决像素偏移滚动** — 改为 `scrollPositionID` 纯段落 ID 定位
- ❌ **否决 CharacterScanner** — 改为 Cloudflare Workers AI
- ✅ **AI Worker 模型固定** — qwen-2.5-7b-instruct，不在客户端配置
- ✅ **DebugLogger .jsonl 格式** — 每启动一个文件，行追加，方便整体发送
- ✅ **Worker 状态检测** — context menu「测试连接」+ 状态圆点

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
| `(current)` | **feat: 角色卡上下文菜单(合并/删除/重命名) + 自动推荐音色名 + 默认音色兜底** |

## 当前已知问题

1. **worker.js 偶尔空响应** — LLM 复杂场景下返回空, 已添加基础 prompt 降级重试 (需重新部署 `temp/worker.js`)
2. **config voices 为空** — 服务器 `/api/v1/config` 返回 empty voices 列表, 但已添加 `defaultChineseVoices` 兜底, 不影响音色匹配
3. **性别检测准确率** — 取决于 LLM 对角色的理解, `unknown` 时回退名字关键词
