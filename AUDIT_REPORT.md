# FeatureTTSReader — 项目全维度审计报告

**版本**：`125ff3e` (refactor/worker-ai-replace-local-scanner)  
**日期**：2026-07-15  
**基线分支**：main → refactor/worker-ai-replace-local-scanner  
**CI 状态**：✅ GitHub Actions iOS IPA Build 通过

---

## 1. 模块架构

### 1.1 文件结构概览 (Sources/FeatureTTSReaderApp)

| 类别 | 文件 | 核心职责 | 行数(约) |
|------|------|----------|----------|
| **入口/生命周期** | `FeatureTTSReaderApp.swift` | App 启动、DebugLogger 初始化、依赖注入 | 40 |
| **核心状态** | `Store.swift` (ReaderStore) | 单例状态中枢、播放编排、书籍/角色/章节/脚本/缓存/Worker 管理 | 3100+ |
| **数据模型** | `Models.swift` | Book/Chapter/CharacterProfile/ScriptSegment/TTSQueueItem/PlaybackAnchor/枚举 | 500 |
| **持久化** | `PersistenceController.swift` | Core Data 书架/章节/书签存储 | 180 |
| **AI Worker** | `AIWorkerConfig.swift` / `AIWorkerService.swift` | Worker 配置/请求/重试/流式分片 | 300 |
| **TTS 引擎** | `EdgeTTSService.swift` / `EdgeTTSServerConfig.swift` | Edge TTS HTTP API、SSML、服务器健康检查、最快节点选择 | 680 |
| **音频播放** | `AdvancedAudioPlaybackController.swift` | AVAudioPlayer 队列、无缝切换、锁屏控制、状态恢复 | 650 |
| **解析/剧本** | `Parser.swift` / `DramaDirector.swift` / `CharacterAnalyzer.swift` | 本地段落/对话/角色提取、情绪上下文平滑 | 400 |
| **角色管理** | `CharacterAliasManager.swift` / `VoiceMatchUtility.swift` | 别名合并/拆分、性别感知音色自动匹配 | 200 |
| **缓存/调度** | `AIParseCache.swift` / `WorkerRotator.swift` / `SpeculativePlayer.swift` / `SynthesisBuffer.swift` | 解析缓存、多 Worker 轮询、投机播放、保序合成缓冲 | 350 |
| **阅读视图** | `ReaderView.swift` / `ReaderSheets.swift` / `CharacterListView.swift` / `ChapterListView.swift` | 书籍阅读、章节导航、句级高亮/滚动、角色面板 | 1500 |
| **书架/详情** | `BookshelfView.swift` / `BookDetailView.swift` / `CharacterAssignmentView.swift` | 导入/书架、书籍详情/角色扫描/脚本生成/音色分配 | 1000 |
| **TTS 工作台** | `TTSView.swift` / `CharacterRoleCard.swift` / `VoicePickerPopover.swift` | 自定义多角色测试、AI 解析流式合成、音色选择器 | 1200 |
| **设置/工具** | `SettingsView.swift` / `ReaderSettingsViews.swift` / `FontManager.swift` / `TextNormalizer.swift` | 全局设置、字体/主题、文本归一化、调试日志开关 | 800 |
| **工具/辅助** | `DebugLogger.swift` / `Logger.swift` / `PlaybackAnchor.swift` / `ScrollCoordinator.swift` / `TTSUtility.swift` / `DocumentImporter.swift` / `Extensions.swift` | JSONL 日志、锚点同步、滚动协调、语速/音量/音色工具、多编码导入 | 500 |

### 1.2 关键依赖图

```
FeatureTTSReaderApp (MainActor)
├── ReaderStore (NSObject, @MainActor) — 核心单例
│   ├── PersistenceController (Core Data) — 书架/章节/书签
│   ├── EdgeTTSService (actor) — TTS 合成
│   ├── AdvancedAudioPlaybackController (MainActor) — 播放队列
│   ├── AIWorkerService (actor) — AI 剧本解析
│   ├── WorkerRotator — 多 Worker 轮询
│   ├── AIParseCache — 解析缓存 (文件)
│   ├── SpeculativePlayer — 投机播放
│   └── SynthesisBuffer (actor) — 保序合成
├── ReaderView / TTSView / BookshelfView / BookDetailView / SettingsView
└── DebugLogger (enum, 非隔离) — 全局 JSONL 日志
```

### 1.3 并发模型

| 组件 | 隔离域 | 说明 |
|------|--------|------|
| `ReaderStore` | `@MainActor` | 所有 `@Published` 状态、UI 绑定 |
| `EdgeTTSService` | `actor` | 网络请求、服务器选择、缓存 |
| `AdvancedAudioPlaybackController` | `@MainActor` | AVAudioPlayer delegate、队列操作 |
| `AIWorkerService` | `actor` | HTTP 请求、重试、上下文拼接 |
| `WorkerRotator` | `actor` | 轮询索引、成功/失败标记 |
| `AIParseCache` | `actor` | 文件读写、键值缓存 |
| `SpeculativePlayer` | `actor` | 投机状态、替换协调 |
| `SynthesisBuffer` | `actor` | 并发合成结果按序入队 |

> ⚠️ **风险**：Store 持有大量 `@Published` 且直接在 `Task { @MainActor in }` 中调用 actor 方法，容易造成主线程阻塞或优先级反转。

---

## 2. 核心功能支柱

### 2.1 书籍导入与书架 (`BookshelfView` + `DocumentImporter`)

- **多编码支持**：GB18030 / UTF-8 / Big5 自动探测 (`DocumentImporter.importFile`)
- **章节自动切分**：`Store.extractChapters` 正则匹配 `第xxx章` / `第xxx回` / `Chapter xxx`
- **Core Data 持久化**：Book 元数据存 SQLite，全文存文件 (`PersistenceController.saveBooks`)
- **排序/筛选**：最近阅读 / 标题 / 进度 (`SortOption`)

### 2.2 角色提取与剧本生成 (双通道)

| 通道 | 入口 | 核心逻辑 | 产出 |
|------|------|----------|------|
| **AI Worker (主)** | `Store.scanCharacters()` → `AIWorkerService.processChapter` | 文本分片 → 逐片 POST Cloudflare Worker (qwen-2.5-7b) → 合并 AISegment[] → 性别推断 → 自动匹配音色 | `characters: [CharacterProfile]` + `scriptSegments: [ScriptSegment]` |
| **本地扫描 (备用/CharacterAssignmentView)** | `CharacterAssignmentView.startScan()` → `CharacterAnalyzer` | 候选提取(正则/说话动词) → AC自动机频率统计 → 多段落投票(性别/年龄/语气) → 头衔合并/别名解析 | 同结构，准确率依赖启发式 |

> **关键决策**：AI Worker 模型固定 qwen-2.5-7b-instruct，客户端不暴露模型选择。

### 2.3 多角色 TTS 合成与播放管线

```
ReaderView.playChapterWithAI / playChapterStreaming
  → sliceText (Store/AIWorkerService)
  → sendRequest (AIWorkerService) [重试 2 次]
  → mergeConsecutiveAISegments (同 speaker/emotion/tone 合并)
  → assignVoicesToSegments (首片自动匹配音色)
  → withThrowingTaskGroup 并发合成 (EdgeTTSService.synthesize)
  → SynthesisBuffer.insert (按 idx 保序)
  → appendToQueue / playQueue (AdvancedAudioPlaybackController)
  → AVAudioPlayer 逐个播放 → delegate 驱动下一句
```

**关键优化**：
- **投机播放**：首片旁白预设音色零等待启动，AI 返回后无缝替换 (`SpeculativePlayer`)
- **懒加载窗口**：队列剩余 ≤ 阈值(默认 10)触发下一片解析 (`playChapterWithAI` line 2002)
- **跨章预取**：当前章队列耗尽自动拉取下一章 (`playChapterWithAI` line 2052)
- **音色变更重合成**：`resynthesizingSpeaker` didSet 触发增量重合成

### 2.4 阅读体验 (`ReaderView`)

- **段落级渲染**：`LazyVStack` + `scrollPositionID` (`ch_{chap}_p_{para}`) 纯 ID 定位
- **句级高亮/滚动**：活跃段落背景色 + 当前句更深高亮；`scheduleAutoScrollUpdate` 80ms 防抖
- **交互**：双击朗读、长按选词、区域点击翻页、沉浸模式
- **锚点同步**：`PlaybackAnchor(bookID, chapterIndex, paragraphIndex, sentenceIndex, speakerID)` 跨栈同步

### 2.5 自定义 TTS 工作台 (`TTSView`)

- **Worker 管理**：列表/编辑/测试连接/设为默认/删除，状态圆点 (绿/黄/灰/红)
- **一站式流式**：文本输入 → AI 解析 → 首片分配音色 → 合并 → 并发合成 → 边播边合成
- **全局控制**：语速/音量/重叠滑块，实时叠加到角色基础值
- **VoicePickerPopover**：List 替代 Menu 突破 HStack 限制，性别徽标、中文名主显

---

## 3. 视图层级与职责

| 视图 | 文件 | 父级 | 核心状态 | 备注 |
|------|------|------|----------|------|
| `BookshelfView` | `BookshelfView.swift` | Tab/Nav | `books`, `sortOption`, `searchText` | 网格/列表切换、导入、删除 |
| `BookDetailView` | `BookDetailView.swift` | Bookshelf | `book`, `chapters`, `readerCover` | 章节列表、角色面板入口、打开阅读器 |
| `ReaderView` | `ReaderView.swift` | BookDetail(fullScreenCover) | `currentChapter`, `scrollPositionID`, `isAudioMode`, `playbackSpeed` | 核心阅读+播放控制 |
| `ReaderSheets` | `ReaderSheets.swift` | ReaderView | `showCharacterList`, `showSettings`, `showTOC` | 底部工具栏展开的各类 Sheet |
| `CharacterListView` | `CharacterListView.swift` | ReaderSheets | `characters`, `availableVoices`, `aiCacheAvailable` | 扫描/生成脚本/分配音色/试听 |
| `CharacterAssignmentView` | `CharacterAssignmentView.swift` | BookDetail | 本地扫描流水线、角色编辑、导入导出 | 传统本地扫描入口 |
| `TTSView` | `TTSView.swift` | Tab | `customWorkerSegments`, `customCharacterVoices`, `selectedWorkerID` | 独立测试沙箱，与 Store 隔离 |
| `SettingsView` | `SettingsView.swift` | Tab | 大量 `@AppStorage`/`UserDefaults` | 外观/交互/语音/书架/字体/数据/关于 |

---

## 4. 关键数据流

### 4.1 书籍阅读 → 朗读 (AI Worker 路径)

```
User: 点击「从本页听」/悬浮播放键
  → ReaderView.startPlayback(fromParagraphIndex)
  → Store.startPlaybackTask(chapter, fromParagraphIndex)
  → useAI ? playChapterWithAI : playChapterStreaming
  → [AI 路径] sliceText → sendRequest(重试) → mergeSegments
  → assignVoices → 并发合成 → SynthesisBuffer → appendToQueue
  → AdvancedAudioPlaybackController.playQueue
  → AVAudioPlayerDelegate → currentAnchor → Store.currentParagraphIndex/SentenceIndex
  → ReaderView 观察 → scheduleAutoScrollUpdate → scrollPositionID 更新
  → ChapterContentView 重渲染 → 段落/句高亮
```

### 4.2 角色编辑 → 重合成

```
User: CharacterListView 修改角色 voiceID
  → Store.characters 更新 → saveState
  → resynthesizingSpeaker = speakerName (didSet)
  → resynthesizeSpeaker: 筛选该角色段落 → 并发重合成 → replaceQueueItems
  → 播放器无缝替换后续队列项
```

### 4.3 跨章节连播

```
播放器队列耗尽 → audioControllerDelegate.playbackQueueDidFinish
  → Store 监听 → currentChapterIndex < chapters.count-1 ?
  → navigateToChapter(next) → startPlayback(nil)
  → 新章节 playChapterWithAI (懒加载)
```

---

## 5. 隐患与风险 (Security / Stability / Concurrency)

| # | 类别 | 位置 | 描述 | 严重度 |
|---|------|------|------|--------|
| H1 | **安全** | `AIWorkerConfig.authKey` | 明文存储 UserDefaults，无 Keychain 加密；Cloudflare Worker 密钥泄露风险 | 🔴 Critical |
| H2 | **安全** | `EdgeTTSServerConfig.apiKey` | 同上，TTS 中继服务密钥明文 | 🔴 Critical |
| H3 | **稳定性** | `Store.observeAudioController` | Combine sink 捕获 `self` 无 `[weak self]`，Store 为单例虽不泄漏但模式危险 | 🟡 Medium |
| H4 | **稳定性** | `AdvancedAudioPlaybackController` | `AVAudioPlayer` delegate 在非主线程回调，内部 `@MainActor` 方法需 `Task { @MainActor in }` 包装，已基本覆盖但需审计 | 🟡 Medium |
| H5 | **并发** | `Store.playChapterWithAI` | `TaskGroup` 中捕获 `audioController` (MainActor) 跨 actor 调用，虽有 `AudioControllerRef` 但竞态窗口存在 | 🟡 Medium |
| H6 | **并发** | `SynthesisBuffer` | `OSAllocatedUnfairLock` 保护但 `insert` 与 `flushRemaining` 可能在不同 Task 并发，需验证线性化 | 🟡 Medium |
| H7 | **资源泄漏** | `Store.autoSaveTimer` | `Timer` 未在 deinit 显式 invalidate，虽单例生命周期=进程但模式不佳 | 🟢 Low |
| H8 | **数据完整性** | `Book.text` 不编码 JSON | 依赖 Core Data 文件存储，`Book` Codable 故意丢弃 `text`，若 Core Data 损坏全文丢失 | 🟡 Medium |
| H9 | **网络** | `EdgeTTSService.healthCheck` | 3s 超时硬编码，局域网不稳定时误判；无重试/指数退避 | 🟢 Low |
| H10 | **隐私** | `DebugLogger` | 每次启动生成 `.jsonl` 写入 Documents/debug/，含完整请求/响应文本，可能泄露小说内容 | 🟡 Medium |

---

## 6. 已知/潜在 Bug

| # | 模块 | 现象 | 根因 | 状态 |
|---|------|------|------|------|
| B1 | **EdgeTTS** | 合成请求 404 | `synthesize`/`synthesizeSSML` 拼接路径为 `/tts` 而服务端实际为 `/api/v1/tts` | ✅ 已修复 `125ff3e` |
| B2 | **AI Worker** | 结果截断不重试 | `Store.playChapterWithAI` 缺少 TTSView 同款 `while retryCount <= 2` 逻辑 | ✅ 已修复 `125ff3e` |
| B3 | **合并段落** | 连续同角色段落错误插入 `。` | `mergeConsecutiveAISegments` 仅检查 `。！？`，对话结尾 `：`/`……` 误加句号 | ✅ 已修复 `125ff3e` (改为直接拼接) |
| B4 | **依赖倒置** | Store 引用 `TTSView.rateOffset/pitchOffset/resolvedVolume` | 视图层函数被数据层反向依赖 | ✅ 已修复 `125ff3e` (提取 `TTSUtility`) |
| B5 | **Sendable** | `FirstPlayFlag @unchecked Sendable` 可变 var | 并发访问竞态 | ✅ 已修复 `125ff3e` (`OSAllocatedUnfairLock`) |
| B6 | **句级高亮缺失** | 仅段落高亮，无句级视觉标记 | `ChapterContentView.paragraphView` 整段渲染 | ✅ 已修复 `125ff3e` (活跃段落拆句渲染) |
| B7 | **DebugLogger 无开关** | 无法关闭日志，磁盘持续增长 | 无 `isEnabled` Guard，无 Settings 入口 | ✅ 已修复 `125ff3e` |
| B8 | **Worker 配置** | `model` 字段保留但固定 qwen-2.5-7b，UI 仍显示可编辑 | `WorkerEditView` 含 model Picker 但 Worker 端忽略 | 🟡 未修 |
| B9 | **章节缓存键** | `bookChaptersCache` 以 `UUID` 为键，但 `chaptersForBook(text:)` 传入全文，全文变更不失效 | 仅缓存命中不校验内容哈希 | 🟡 未修 |
| B10 | **TTS 缓存** | `ttsCache: [String: URL]` 无大小/时间驱逐，仅 200 条上限 | 长期运行内存/磁盘增长 | 🟢 Low |
| B11 | **投机替换** | `SpeculativePlayer.realSegmentsArrived` 仅标记，若投机项已播放完则无法替换 | 设计假设投机项未播放，极端网络快时可能失效 | 🟡 未修 |
| B12 | **语音性别不匹配** | `VoiceMatchUtility.autoMatchVoice` 仅按 gender 过滤，未考虑 `VoiceGender` vs `CharacterGender` 枚举差异 | 两套性别枚举未统一映射 | 🟢 Low |
| B13 | **章节导航** | `navigateToChapter` 直接赋值 `currentChapter` 触发 `chapterContent` 重建，可能丢失滚动位置 | 依赖 `scrollPositionID` 双次赋值，竞态 | 🟡 未修 |
| B14 | **全文搜索** | 书架搜索仅匹配标题，不搜正文 | `BookshelfView` `searchText` 仅过滤 `book.title` | 🟢 Low (功能缺失) |

---

## 7. 逻辑错误与边界处理缺陷

| # | 位置 | 问题 | 影响 |
|---|------|------|------|
| L1 | `Store.playChapterWithAI` line 1846 | `sliceText` 以字符数切片，可能将一句话切成两片，导致上下文断裂 | AI 解析上下文不连贯，说话人识别错误 |
| L2 | `AIWorkerService.sendRequest` | `context` 仅传前 200 字，长篇章上下文丢失 | 后片段角色一致性下降 |
| L3 | `CharacterAnalyzer.estimateAttributes` | 基于关键词投票，误判率高(如「小李」→女性) | 角色性别/年龄/语气错误，音色自动匹配偏离 |
| L4 | `VoiceMatchUtility.autoMatchVoice` | 可用音色为空时回退硬编码 2 个，无性别区分 | 全员用同一音色 |
| L5 | `mergeConsecutiveAISegments` | 合并时 `gender` 取 `current.gender` 忽略后段差异 | 同角色不同性别片段错误合并 |
| L6 | `AdvancedAudioPlaybackController.playQueue` | `preloadNext()` 预加载下一项音频数据，但 `queue` 为空时仍尝试访问 `queue[0]` | 崩溃风险 (已有 `guard !queue.isEmpty`) |
| L7 | `ReaderView.selectSentence` | `audioController.skipToSegment(at:)` 以段落索引跳转，但队列按 `ScriptSegment` 索引 | 跳转目标可能不准 |
| L8 | `Store.buildScript` | `parseDialogueSegments` 正则 `["""]` 匹配中文引号，但繁体/竖排引号 `「」` 未覆盖 | 台港小说对话识别缺失 |
| L9 | `AIWorkerService.sliceText` | 硬切字符数，不保证句边界，`focusFromParagraph` 仅首片传递 | 切片内语义破碎 |
| L10 | `WorkerRotator.nextWorker` | 仅轮询 `isEnabled`，不考虑 `priority` 字段 | 高优先级 Worker 未优先使用 |

---

## 8. 差体验 / UX 债务

| # | 场景 | 现状 | 期望 | 优先级 |
|---|------|------|------|--------|
| U1 | **首次导入** | 文件选择后无进度条，大文件(>10MB)卡死感知 | 进度指示 + 后台解析 | 🔴 High |
| U2 | **角色扫描** | AI Worker 扫描全书无进度、无取消、失败无降级提示 | 分步进度条、取消按钮、失败自动回退本地扫描 | 🔴 High |
| U3 | **朗读起点** | 悬浮键总是从章头开始，「从本页听」仅滑离时出现 | 显眼的「继续阅读」/「从当前段落播放」入口 | 🟡 Medium |
| U4 | **句级高亮** | 仅当前句加深背景，无下划线/字号/颜色区分，阅读时难以快速定位 | 当前句加粗/下划线/高对比色 | 🟡 Medium |
| U5 | **播放控制** | 底部栏按钮密集(上/下句、上/下段、章节滑块、倍速、音量、重叠)，误触率高 | 折叠进阶控制、保留核心播放/暂停/±15s | 🟡 Medium |
| U6 | **音色选择** | VoicePickerPopover 列表无搜索、无试听、中文名/英文ID 混排 | 搜索框、试听按钮、分组(中文/英文/方言) | 🟡 Medium |
| U7 | **设置同步** | 语速/音量/重叠在 TTSView 与 ReaderSettingsView 双向同步，但 `UserDefaults` 键名不统一 | 统一键名、单一数据源 | 🟢 Low |
| U8 | **错误提示** | 网络/解析/合成失败仅 `statusMessage` 文本，无分类/可操作建议 | 错误码→用户友好文案+重试/切换服务器/联网检查 | 🟡 Medium |
| U9 | **书架排序** | 仅 3 种排序，无「自定义排序」(长按拖拽) | 拖拽排序持久化 | 🟢 Low |
| U10 | **沉浸模式** | 状态栏隐藏但底部工具栏仍在，非真全屏 | 真全屏+边缘手势呼出控制 | 🟢 Low |
| U11 | **多书并行** | 仅单书单章播放，切书需停止当前 | 后台预加载下一书、多任务队列 | 🟢 Low |
| U12 | **导出/分享** | 仅角色配置 JSON 导出，无音频/脚本/书签导出 | 支持导出 MP3 合集、带时间戳脚本、书签 | 🟢 Low |

---

## 9. 技术债务清单 (按模块)

### Store.swift (3100+ 行) — **急需拆分**
- [ ] 拆分 `PlaybackCoordinator` (播放编排)
- [ ] 拆分 `CharacterManager` (角色增删改查/别名/扫描)
- [ ] 拆分 `BookManager` (书架/章节/进度/书签)
- [ ] 拆分 `TTSEngine` (合成缓存/服务器选择/SSML 构建)
- [ ] 将 `@Published` 归类到各子 Store，主 Store 仅组合

### EdgeTTSService.swift
- [ ] 抽象 `TTSEngine` 协议，便于接入 CosyVoice/系统 TTS
- [ ] 统一请求/响应 DTO，移除散落的字典拼装
- [ ] 健康检查增加重试、指数退避、并发限制

### AIWorkerService.swift
- [ ] 统一重试策略为可配置 `RetryPolicy` (次数/退避/可重试错误码)
- [ ] `context` 管理改为滑动窗口而非仅前 200 字

### AdvancedAudioPlaybackController.swift
- [ ] 替换 `AVAudioPlayer` → `AVAudioEngine` + `AVAudioPlayerNode` (支持变速/淡入淡出/精确 seek)
- [ ] 音频会话类别/模式集中管理，避免与系统音频冲突

### ReaderView.swift
- [ ] `ChapterContentView` 提取为独立文件，支持句级点击/长按/复制
- [ ] 滚动锚点改用 `ScrollViewReader.proxy.scrollTo(anchor:)` 官方 API

### TTSView.swift
- [ ] 与 ReaderView 共享 `CharacterRoleCard` / `VoicePickerPopover` / `SynthesisBuffer` (已在计划中)

### DebugLogger.swift
- [ ] 增加分级 `LogLevel` (debug/info/warn/error) 与采样率
- [ ] 支持远程上传/导出 zip

---

## 10. 测试覆盖现状

| 层级 | 覆盖 | 缺口 |
|------|------|------|
| **单元测试** | 无 | 核心算法(分句/合并/音色匹配/别名解析)无测试 |
| **集成测试** | 无 | Store 播放流程、跨章切换、投机替换无自动化验证 |
| **UI 测试** | 无 | 关键用户流(导入→扫描→播放→高亮)无截图回归 |
| **契约测试** | 无 | AI Worker / Edge TTS HTTP 接口无 schema 验证 |

---

## 11. 部署与运维

| 项目 | 现状 | 建议 |
|------|------|------|
| **CI/CD** | GitHub Actions `xcodebuild` + `xcbeautify` + IPA 上传 | 增加 `swiftlint`/`swift-format` 阶段、单元测试门禁 |
| **版本管理** | 无自动化，手动改 `CFBundleShortVersionString` | `fastlane` + `match` 签名管理、自动构建号 |
| **崩溃收集** | 无 (TestFlight 仅苹果端) | 接入 Sentry / Firebase Crashlytics |
| **遥测** | 无 | 关键漏斗(导入成功率/扫描成功率/播放完成率)埋点 |
| **日志归档** | DebugLogger 本地 JSONL，7 天清理 | 可选上传、用户授权、压缩加密 |

---

## 12. 优先级建议 (P0→P3)

| 优先级 | 任务 | 预估工时 | 备注 |
|--------|------|----------|------|
| **P0** | 密钥入 Keychain (H1/H2) | 0.5d | `KeychainAccess` / `GenericPasswordQuery` |
| **P0** | Store 拆分最小可行 (PlaybackCoordinator) | 2d | 先剥离播放编排，降低单文件复杂度 |
| **P0** | 单元测试骨架 + 核心算法覆盖 | 2d | `splitBlockIntoSentences`/`mergeConsecutiveAISegments`/`autoMatchVoice` |
| **P1** | 角色扫描进度/取消/降级 (U2) | 1.5d | `ProgressView` + `Task.cancel()` + fallback 本地扫描 |
| **P1** | 句级高亮视觉增强 (U4) | 0.5d | 加粗/下划线/高对比色 |
| **P1** | 播放控制栏折叠重构 (U5) | 1d | 分栈：核心行 + 进阶 Popover |
| **P1** | 错误分类与可操作提示 (U8) | 1d | `ErrorPresenter` 统一入口 |
| **P2** | VoicePickerPopover 搜索/试听/分组 (U6) | 1.5d | 复用 `EdgeTTSService.fetchVoices` 缓存 |
| **P2** | 章节切片保句边界 (L1/L9) | 1d | `sliceText` 改为句边界对齐 |
| **P2** | AVAudioEngine 迁移 (音频控制器) | 3d | 支持变速/淡入淡出/精确 seek |
| **P3** | 多书并行/后台预加载 (U11) | 3d | 播放队列抽象为 `PlaybackSession` |
| **P3** | 导出音频/脚本/书签 (U12) | 2d | `AVAssetExportSession` 合并 MP3 |

---

## 13. 附录：关键文件行号索引 (供快速定位)

| 文件 | 关键函数/结构 | 行号范围 |
|------|--------------|----------|
| `Store.swift` | `playChapterWithAI` | 1731-2067 |
| `Store.swift` | `playChapterStreaming` | 1483-1719 |
| `Store.swift` | `scanCharacters` (AI) | 1081-1160 |
| `Store.swift` | `mergeConsecutiveAISegments` | 2379-2398 |
| `Store.swift` | `observeAudioController` | 245-254 |
| `Store.swift` | `resynthesizeSpeaker` | 2185-2240 |
| `AIWorkerService.swift` | `sendRequest` / `processChapter` | 80-200 |
| `EdgeTTSService.swift` | `synthesize` / `synthesizeSSML` / `healthCheck` | 290-420 |
| `AdvancedAudioPlaybackController.swift` | `playQueue` / `appendToQueue` / `playNextSeamlessly` | 160-250 |
| `ReaderView.swift` | `startPlayback` / `scheduleAutoScrollUpdate` | 723-740 / 704-721 |
| `ReaderView.swift` | `ChapterContentView` / `paragraphView` | 761-850 |
| `CharacterAssignmentView.swift` | `startScan` / `CharacterAnalyzer` | 240-383 |
| `VoiceMatchUtility.swift` | `autoMatchVoice` | 30-80 |
| `DebugLogger.swift` | `log` / `isEnabled` | 45-87 |
| `SettingsView.swift` | 调试日志 Toggle | 289-310 |
| `TTSUtility.swift` | `rateOffset` / `pitchOffset` / `resolvedVolume` / `resolveGender` / `isResultComplete` | 5-92 |

---

**审计人**：opencode (自动化 + 人工复核)  
**下次复核节点**：Store 拆分完成后、AVAudioEngine 迁移前