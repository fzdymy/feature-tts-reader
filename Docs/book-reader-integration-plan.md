# 书籍朗读界面 — 多角色 TTS 模块整合方案

## 一、现状分析

### 当前书籍朗读 TTS 流程（ReaderView + ReaderStore）

```
scanCharacters() → AI Worker → [CharacterProfile]
         ↓
buildScript() → 本地 parseDialogueSegments() → [ScriptSegment]
         ↓
playChapterStreaming() → 逐句 Edge TTS + AudioPrefetcher → 逐句入队
         ↓
AVAudioPlayer delegate 驱动播放 + 段落/句子高亮
```

**问题：**
1. **本地解析 vs AI 解析** — `parseDialogueSegments()` 基于引号匹配+正则，准确率远低于 AI Worker 的语义理解
2. **逐句合成** — 每次合成一个句子，HTTP 开销大，无法批量
3. **无段落合并** — 相同说话人连续段落未合并，导致不必要的切换
4. **角色管理弱** — 角色面板只有基础列表，无音色选择器、无别名系统、无音量/语速调节
5. **缺失控制** — 无全局语速/音量/重叠滑块、无播放队列状态

### 当前 TTSView 多角色模块优势（待移植）

| 特性 | TTSView | ReaderView |
|------|---------|------------|
| AI 语义分段 | ✅ `processCustomWithWorker()` | ❌ 本地 `parseDialogueSegments` |
| 并发批量合成 | ✅ `withThrowingTaskGroup` + `SynthesisBuffer` | ❌ 逐句串行 |
| 段落合并 | ✅ `mergeConsecutiveSegments()` | ❌ 无 |
| 角色音色选择器 | ✅ `CharacterRoleCard` + `VoicePickerPopover` | ❌ 无（只有推荐） |
| 别名系统 | ✅ `characterAliases` + 合并/分离 | ❌ 无 |
| 全局语速滑块 | ✅ `multiRoleGlobalRate` (-10~10) | ❌ `playbackSpeed` 无 UI |
| 全局音量滑块 | ✅ `globalVolumeOffset` | ❌ 无 |
| 重叠时间调节 | ✅ `globalOverlapMs` (0-500ms) | ❌ 固定 |
| 播放队列状态 | ✅ `queueCount` | ❌ 无 |
| 性别检测 | ✅ `AISegment.gender` | ❌ 无 |
| 重试截断结果 | ✅ AI Worker 重试逻辑 | ❌ 无 |

---

## 二、整合目标

将 TTSView 的**多角色 TTS 通用模块**移植到 ReaderView 中，替换现有 `playChapterStreaming()` 流程，保留 ReaderView 的**书籍特有功能**（段落滚动、高亮同步、章节导航、书签）。

### 保留不动
- `BookshelfView` / `BookDetailView` — 书籍列表和详情
- `ChapterContentView` — 段落渲染（保持文本高亮功能）
- `ReaderSheets` — 设置/字体/目录/角色面板入口
- `ReaderSettingsView` — 排版/字体/背景等阅读设置
- `ChapterListView` — 目录
- `PlaybackAnchor` — 高亮同步机制
- `AdvancedAudioPlaybackController` — 播放引擎（复用）
- `EdgeTTSService` — TTS 合成（复用）

### 替换
- **`playChapterStreaming()`** → 改为 AI Worker 逐片分段 + 并发合成（类似 `processCustomWithWorker`）
- **`parseDialogueSegments()`** → 由 AI Worker 返回 `AISegment[]`
- **角色面板** → 用 `CharacterRoleCard` + 别名系统替换
- **底部控制栏** → 增加语音/语速/音量/重叠控制

### 新增
- 书籍朗读模式下可调全局语速/音量/重叠滑块
- 播放入口增加"AI 解析"步骤（扫描→解析→合成）
- 播放队列状态显示（queueCount）

---

## 三、UI 改造方案

### 布局架构（修改 `ReaderOverlayView`）

```
┌─ 朗读模式下底部栏（audioBottomBar）原结构 ─────────────────┐
│  [上一章] ████████████░░░░░ [下一章]                          │
│  当前句子文本（2行）                                            │
│  ● 正在朗读 / 已暂停  "第X段·第Y句"                              │
│  [上一句] [下一句] [▶/⏸] [上一段] [下一段]                    │
│  [目录] [主题] [设置] [字体]                                    │
└────────────────────────────────────────────────────────────┘
```

**修改后结构：**

```
┌─ 朗读模式下底部栏（audioBottomBar）新结构 ────────────────────┐
│  [上一章] ████████████░░░░░ [下一章]                          │
│  当前句子文本（2行）                                            │
│  ● 正在朗读  "王明说：你好"  "第3段·第5句"                      │
│  ┌──────────── 播放控制 + 角色/设置融入 ────────────┐          │
│  │  [⏮] [◀] [▶/⏸] [▶] [⏭]  │ 队列:N  │ [👤] [⚙️] │          │
│  └────────────────────────────────────────────────┘          │
│  [目录] [角色] [设置] [速度±] [音量±] [重叠]                   │
└────────────────────────────────────────────────────────────┘
```

### 新增/修改的 UI 组件

#### 1. 角色面板（替换现有 `characterPanelSheet`）
```
┌─ Sheet: 角色管理 ──────────────────────────────────────┐
│  [扫描角色] [AI 解析当前章节] [一键配音]                    │
│                                                          │
│  ┌─ 小明 ──────────── [♂] ─── [⋮] ┐                    │
│  │  音色：晓晓 (zh-CN-Xiaoxiao)    │                    │
│  │  [小晓] [晓萱] [晓伊] ...        │  ← voice picker    │
│  │  别名：明明                      │                    │
│  │  ┌─ 合并到... ─┐ ┌─ 分离角色 ─┐ │                    │
│  └──────────────────────────────────┘                    │
│  ┌─ 李华 ──────────── [♀] ─── [⋮] ┐                    │
│  │  ...                             │                    │
│  └──────────────────────────────────┘                    │
└────────────────────────────────────────────────────────┘
```

#### 2. 设置面板（修改 `ReaderSettingsView` + 新增朗读设置 section）
```
┌─ 朗读设置（ReaderSettingsView 新增 Section） ────────────┐
│  朗读设置                                                  │
│  语速： [━━━━━●━━━━━]  +5                                 │
│  音量： [━━━●━━━━━━━━]  -2dB                              │
│  段落重叠： [━━●━━━━━━]  80ms                             │
│  [AI Worker 配置 →]  (跳转语音引擎页面)                    │
│  [Edge TTS 服务器 →]  (跳转语音引擎页面)                   │
└────────────────────────────────────────────────────────┘
```

#### 3. 底部控制栏新增按钮
- **速度±**：点击展开语速滑块 Popover
- **音量±**：点击展开音量滑块 Popover
- **重叠**：点击展开重叠滑块 Popover
- **队列:N**：显示当前队列中待播放数（`queueCount`）

---

## 四、核心模块划分与复用策略

### 模块 A：AI 分段 + 并发合成（新，从 TTSView 抽取）

**来源：** TTSView.`processCustomWithWorker()` + `SynthesisBuffer` + `synthesizeAndPlayCustom()`

**改造为通用函数（放到 ReaderStore 或新 Service 文件）：**

```swift
func processChapterWithWorker(
    chapter: BookChapter,
    characters: [CharacterProfile],
    voiceAssignments: [String: String],  // speakerName → voiceID
    workerConfig: AIWorkerConfig,
    serverID: UUID,
    globalRate: Double,
    globalVolume: Double,
    overlapMs: Double
) async throws -> [TTSQueueItem]
```

**流程：**
1. `sliceText()` → N个分片
2. 逐片 `sendRequest()` → `AISegment[]`
3. `mergeConsecutiveSegments()` → 合并相同 speaker/emotion/tone
4. `assignVoicesToSegments()` → 为每段分配音色
5. 并发 `withThrowingTaskGroup` → 每段 `EdgeTTSService.synthesize()`
6. `SynthesisBuffer` → 按顺序组装 `TTSQueueItem`（带 paragraphIndex/sentenceIndex）
7. 返回 `[TTSQueueItem]` → 交给 `appendToQueue()`

### 模块 B：角色管理 UI（从 TTSView 抽取）

**来源：** TTSView.`customMultiRoleSection` 中的角色管理部分
- `CharacterRoleCard`（voice picker + gender badge + 删除按钮）
- 合并/分离/重命名/删除
- 别名系统

**改造为通用组件（放入单独文件 `CharacterRoleCard.swift` / `CharacterManagementView.swift`）：**

```swift
struct CharacterRoleCard: View {
    let character: CharacterProfile
    @Binding var voiceAssignments: [String: String]
    let availableVoices: [EdgeVoiceInfo]
    let onMerge: (String) -> Void       // 合并到另一个角色
    let onSplit: () -> Void              // 分离别名
    let onRename: (String) -> Void
    let onDelete: () -> Void
    let onReassignVoice: (String) -> Void
}
```

### 模块 C：全局 TTS 设置控制（从 TTSView 抽取）

**来源：** TTSView 的 `@AppStorage` 全局设置
- `multiRoleGlobalRate` → `@AppStorage("globalRate")`
- `globalVolumeOffset` → `@AppStorage("globalVolume")`
- `globalOverlapMs` → `@AppStorage("globalOverlap")`

**复用：** 直接使用相同的 `@AppStorage` key，ReaderView 和 TTSView 共享设置

### 模块 D：VoicePickerPopover（已存在）

**来源：** TTSView.`VoicePickerPopover`（第 2469-2510 行）

**位置：** 已在 TTSView.swift 底部，可直接复用（需提取到单独文件或保持文件内访问）

---

## 五、实施步骤

### 第一步：抽取通用组件（无功能变更）
1. 将 `VoicePickerPopover` 移到 `CharacterRoleCard.swift`（新建）
2. 将 `CharacterRoleCard` 从 TTSView 内联代码抽取为独立 View
3. 将 `SynthesisBuffer` actor 抽取为文件内/独立 actor
4. 确认所有依赖（`EdgeVoiceInfo`, `AISegment`, `TTSQueueItem`）已导入

### 第二步：修改 ReaderStore 播放流程
1. 在 `ReaderStore` 中添加新的播放入口（不破坏旧的 `playChapterStreaming`）
2. 新方法 `playChapterWithAI(chapter:fromParagraphIndex:)`：
   - 调用 `AIWorkerService.processChapter()` 获取 `AISegment[]`
   - 调用 `mergeConsecutiveSegments()`
   - 调用 `assignVoicesToSegments()`（基于 `store.characters` 的 voiceID）
   - 并发合成 + `SynthesisBuffer` → `[TTSQueueItem]`
   - 调用 `audioController.playQueue(items)`
3. 将 `TTSQueueItem` 的 `paragraphIndex`/`sentenceIndex` 正确关联到原文位置

### 第三步：替换 ReaderView 角色面板
1. 将 `characterPanelSheet`（ReaderView 第 215 行）内容替换为角色管理 UI
2. 集成 `CharacterRoleCard` + 合并/分离/重命名/删除
3. 添加「AI 解析当前章节」按钮（调用 `processChapterWithAI` 但不播放，仅预览角色）
4. 保持原有「扫描角色」「一键配音」按钮

### 第四步：扩展 ReaderView 底部控制栏
1. `audioBottomBar` 增加：
   - 速度按钮（显示当前值，点击弹出 Picker/滑块）
   - 音量按钮
   - 重叠按钮
   - 队列数标签
2. 移除旧 `playbackSpeed`（使⽤ `globalRate` 统⼀控制）
3. `floatingAudioControls` 增加角色按钮快捷入口

### 第五步：将朗读设置加入 ReaderSettingsView
1. 在 `ReaderSettingsView` 末尾添加「朗读设置」Section
2. 语速/音量/重叠滑块
3. AI Worker 配置入口（深链接到 TTSView）

### 第六步：迁移播放控制到新流程
1. 修改「播放/从头听到」按钮，默认调用新的 AI 流程
2. 保留旧的 `playChapterStreaming` 作为回退（设置中可选「本地解析」模式）
3. 调整 `startPlayback(fromParagraphIndex:)` 以支持新的分段模式

### 第七步：测试与打磨
1. 角色管理面板操作（合并/拆分/改名/删除）
2. 音色选择器联动
3. 语速/音量/重叠实时生效
4. 段落高亮同步
5. 章节切换时自动停止/重新解析
6. 从中间段落开始播放（`fromParagraphIndex`）

---

## 六、与现有系统的集成

### 1. 与 `AdvancedAudioPlaybackController` 的集成

新流程生成的 `TTSQueueItem` 必须包含：
- `paragraphIndex: Int?` — 用于高亮同步
- `sentenceIndex: Int?` — 用于高亮同步
- `segmentIndex: Int` — 用于队列顺序

### 2. 与 `CharacterProfile` 的兼容

TTSView 用 `[String: String]`（角色名→音色ID）管理音色分配。
ReaderStore 用 `[CharacterProfile]`（含 `voiceID: String`）。
需在 `CharacterProfile` 中确认已有 `voiceID` 字段，或将 `voiceAssignments` 存放在 `UserDefaults` 中与角色一一对应。

### 3. 与现有 `AudioPrefetcher` 的关系

新流程使用 `SynthesisBuffer` 保序，不再需要滑动窗口 `AudioPrefetcher`。
`AudioPrefetcher` actor 可保留作为回退模式（本地解析模式）使用。

### 4. 别名系统集成

目前 `CharacterProfile` 已有 `alias: [String]`。TTSView 的 `characterAliases: [String: String]`（别名→主名）需要与 `CharacterProfile.alias` 同步。
采用单向同步：`TTSView` 的别名操作写回 `CharacterProfile.alias`。

---

## 七、文件改动清单

| 文件 | 改动类型 | 说明 |
|------|----------|------|
| `TTSView.swift` | 抽取 + 删除 | 移出 `VoicePickerPopover`、`CharacterRoleCard`、`SynthesisBuffer`（文件内引用不变） |
| `CharacterRoleCard.swift` | 新建 | 抽取自 TTSView，通用角色管理卡片 |
| `VoicePickerPopover.swift` | 新建 | 抽取自 TTSView |
| `SynthesisBuffer.swift` | 新建 | 抽取自 TTSView，通用保序缓冲 actor |
| `ReaderStore.swift` | 修改 | 新增 `playChapterWithAI()`，保留旧方法为回退 |
| `ReaderView.swift` | 修改 | 替换底部控制栏、角色面板 |
| `ReaderSettingsViews.swift` | 修改 | 新增朗读设置 Section |
| `ReaderSheets.swift` | 修改 | 调整角色面板 sheet 内容 |

---

## 八、回退方案

保持「本地解析」模式作为可选项：
- `ReaderSettingsView` 新增开关：「AI 语义分段」（默认开启）
- 关闭时使用旧的 `playChapterStreaming()` + `parseDialogueSegments()`
- `@AppStorage("readerUseAI")` 持久化用户选择
