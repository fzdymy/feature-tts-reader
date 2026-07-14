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
6. **无 Worker 轮询** — 不支多个 AI Worker 账号分摊配额
7. **无解析缓存** — 每次打开章节都重新调用 AI Worker，浪费免费额度

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

## 二、核心架构设计（4 个关键考量）

### 考量 1：多 Worker 轮询 — 分摊账号配额

**问题：** AI Worker（Cloudflare Workers AI）有免费额度限制，单一账号容易被限流。

**方案：**

#### 轮询粒度决策：按「章节」轮询，而非按「请求」或「分片」

| 策略 | 优点 | 缺点 |
|------|------|------|
| **按请求（round-robin per request）** | 分摊最均匀 | ① 上下文断裂 — AI Worker 的 `nextContext` 按章节传递，切 Worker 后丢失上下文；② 每次冷启动 LLM 模型加载；③ 调试困难 |
| **按分片（per slice）** | 粒度适中 | 同上，上下文在分片间传递，换 Worker 断裂 |
| **✅ 按章节（per chapter）** | ① 上下文完整，一个 Worker 处理完整章节；② 减少冷启动次数；③ 配额易追踪 | 章节长短不均时负载略偏，但可通过最大分片数兜底 |

**决策：** 按章节轮询，配置 `rotationInterval: Int`（几章换一次 Worker，默认 3，范围 1~10）。当连续处理 N 章后，`WorkerRotator` 切换到下一个健康 Worker。单章超长（分片数 > `maxSlicesPerWorker`，默认 10）时强制切换。

```
Worker Rotator 数据流:
请求到达（第 N 章）
  → WorkerRotator.next(chapterIndex: N) 
  → if N % rotationInterval == 0 → 切换到下一个 Worker
  → 选取当前 Worker URL → sendRequest(url, body, context)
  → 成功则更新上下文 → 继续同章节后续分片使用同一 Worker
  → 失败则标记该 Worker 状态 → 尝试下一个 Worker
  → 全部失败则报错 + 回退本地解析
```

**配置模型扩展（`AIWorkerConfig`）：**
```swift
struct AIWorkerConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var baseURL: String
    var authKey: String
    var maxSliceChars: Int
    var timeout: TimeInterval
    var isDefault: Bool
    var isEnabled: Bool          // 新增：是否参与轮询
    var priority: Int            // 新增：轮询优先级/顺序
}
```

### 考量 2：旁白默认音色 — 零等待启动播放

**问题：** AI Worker 解析需要时间（尤其长文本），用户等待期间无反馈。

**方案：**
- **旁白角色预设**：用户预先为「旁白」（narrator）设定一个默认音色
- **投机流水线**（Speculative Pipeline）：

#### 投机文本长度决策

根据现有 Debug Logger 数据估算（`edge_tts.synthesize_*` + `custom_multi_role.processCustomWithWorker_*`）：

| 阶段 | 耗时估算 |
|------|----------|
| Edge TTS 合成（首段 50~200 字） | 150~300ms（LAN） |
| AI Worker LLM 推理（首片 1000~2000 字） | 1~3s（Cloudflare Workers AI） |
| AI Worker 返回 + 解码 + 重新合成 | 200~500ms |

投机文本需要 **短到快速合成，长到覆盖 AI 延迟**。50~200 字合成只需 ~200ms，但朗读只持续 3~8 秒，若 AI 延迟 >3 秒则出现静音间隔。

**决策：投机首段长度 = 第一个自然段（通常 100~300 字）**。
- 合成耗时 ~300ms，朗读耗时 5~15 秒
- AI Worker 在 1~3 秒内返回，投机段还未播完
- 若 AI 返回后角色与旁白不同，在段落间隙切换，用户无感知
- TTS 并发参数：使用预设旁白音色的 `rate`/`pitch`/`volume`，es 情感为 `neutral`

```
投机文本选择逻辑:
  playChapterWithAI()
    → 取 chapter.text 的第一个段落（split("\n\n")[0]）
    → 若段落 > 500 字，截取前 500 字（避免合成过慢）
    → 用旁白音色合成 → appendToQueue → 立即播放
    → 后台 AI Worker 开始解析
    → 返回后丢弃投机段 → 用真实分段替换
```

**时间线：**
```
t=0   用户点击播放
t=0.1 SpeculativePlayer 截取首段(～200字) → 合成 → appendToQueue
t=0.3 用户听到旁白开始朗读
t=1.5 AI Worker 返回 [AISegment]（首片）
t=1.6 丢弃队列中投机段，批量合成真实分段 → 替换队列
t=2.0 用户听到带角色的朗读（段落间隙无缝切换）

用户感受：点击后 <0.5s 就听到声音，持续播放不中断
```

- **配置存储**：`@AppStorage("narratorVoice")` 保存旁白音色 ID
- **角色面板**：旁白角色默认显示为「旁白」标签，可更换音色

### 考量 3：解析结果缓存 — 避免重复调用 AI Worker

**问题：** 每次打开章节或重新播放都调用 AI Worker，浪费免费额度。

**方案：**
- **缓存键**：`chapterID + text.hashValue`（文本变化时自动失效）
- **缓存存储**：`UserDefaults` 或 JSON 文件（`Documents/ai_cache/`），以 `chapterID.md5` 为文件名
- **缓存内容**：`[AISegment]` 完整数组 + 缓存时间戳
- **缓存策略**：
  - 读取时命中缓存 → 直接使用，零 AI 调用
  - 读取时未命中 → 调用 AI Worker → 写入缓存
  - 用户手动「重新解析」→ 清除该章节缓存 → 重新调用
- **UI 指示**：角色面板显示「缓存命中」状态（绿色小点 / 提示文字）

```
缓存检查流程:
processChapter(chapter) → 计算 cacheKey(chapter.id + text.hash)
         → UserDefaults 中查找 cacheKey
         → 命中? → 反序列化 [AISegment] → 直接返回
         → 未命中? → AI Worker 解析 → 序列化 → 写入缓存 → 返回
```

**数据模型：**
```swift
struct AICacheEntry: Codable {
    let key: String
    let segments: [AISegment]
    let timestamp: Date
    let chapterTitle: String
}
```

### 考量 5：TTS 服务器自动匹配 — 最快节点优先

**问题：** 用户可能配置多个 Edge TTS 服务器（不同地域/网络），固定使用某一个可能不是最快的。

**方案：**
- **延迟探测**：在 app 启动或切换网络时，对所有已配置的 TTS 服务器发一次轻量 health check（`GET /api/v1/tts`），记录响应时间
- **自动选择**：选定延迟最低的服务器作为当前 TTS 目标
- **降级**：当前服务器超时/失败时，切换到次优节点
- **UI**：设置面板开关「TTS 自动匹配」，开启时自动选最快节点，关闭时使用用户手动选择的服务器

```
TTS 服务器选择逻辑:
  启动 / 网络变化
    → 遍历所有 serverConfigs
    → 并发 GET /api/v1/tts（超时 2s）
    → 记录每个服务器的响应延迟（ms）
    → 选取延迟最低且可用的服务器
    → 缓存到 selectedServerID
    → 定时刷新（每 5 分钟或播放结束时）
```

**数据结构扩展：**
```swift
struct EdgeTTSServerConfig: Codable, Identifiable {
    // ... 现有字段
    var lastLatencyMs: Double?    // 新增：最后一次探测延迟
    var lastChecked: Date?        // 新增：探测时间
}
```

### 考量 4：按需懒加载 — 边播边解析

**问题：** 整本书一次性发送给 AI Worker 浪费额度，且无法从中间恢复。

**方案：**
- **懒加载窗口**：仅当播放进度接近缓存区尾部时，才发送下一片到 AI Worker
- **触发条件**：当**未播放的已解析段落数 ≤ N**（N 可配置，默认 5 段）时，请求下一片
- **切片策略**：与现有 `sliceText()` 一致，但只发送「当前播放位置之后的下一片」
- **目的**：避免解析用不上的章节、避免重复解析已读内容

```
懒加载窗口示意:

已播放 ████████████░░░░░░░░░░░░░░░░░░░░░░░░ 未播放
                    ↑
              当前位置

已解析缓冲区:
[=====已解析=====][====已解析=====][待解析]
                   ↑
              剩余 N 段 → 触发请求下一片
```

**状态管理（`ReaderStore` 新增）：**
```swift
// 懒加载状态
var aiParseProgress: [UUID: AIParseState] = [:]  // chapterID → state
var parsedSegmentsBuffer: [AISegment] = []        // 有序的已解析段
var pendingParseChapters: [BookChapter] = []      // 待解析章节队列

enum AIParseState {
    case notRequested
    case parsing(progress: Double)
    case parsed(cacheHit: Bool)
    case failed(Error)
}
```

**跨章节预取：**
- 当前章节播放到 80% 时，自动开始解析下一章
- 下一章有缓存则直接加载，无需 AI 调用

### 数据流全景（整合后）

```
用户点击「朗读」
   ↓
① 投机启动：用旁白音色合成当前段落第一句文本 → appendToQueue → 声音立刻响起
   ↓
② 检查缓存：cacheKey = chapterID + text.hash
   ├─ 命中 → 加载 [AISegment] → 丢弃投机段 → 并发合成 → 替换队列
   └─ 未命中 → 进入步骤③
   ↓
③ AI Worker 轮询调度: WorkerRotator.next() → 选取健康 Worker
   ↓
④ sliceText() → 仅发送当前章节**第一片**（不是全书）
   ↓
⑤ 收到 [AISegment] → 写入缓存
   → mergeConsecutiveSegments()
   → assignVoicesToSegments()（旁白用预设音色，其余角色自动匹配）
   → 丢弃投机段 → 并发合成 → 替换队列
   ↓
⑥ 播放进行中... 监听 parsedSegmentsBuffer 剩余量
   ↓
⑦ 当 未播已解析段 ≤ N（默认 5）→ 发送下一片到 AI Worker（切片位置 = 末尾）
   ↓
⑧ 回到步骤⑤ → 新段合成 → appendToQueue(restItems) 追加到队列尾部
   ↓
⑨ 持续... 直到本章节所有文本解析完毕且播放完毕
   ↓
⑩ 当前章节播放到 80% → 自动预取下一章（检查缓存 → 或 AI 解析）

全程 WorkerRotator 轮询: 每片请求轮流使用不同 Worker URL
```

---

## 三、UI 改造方案

### 布局架构（修改 `ReaderOverlayView`）

**原结构存在的问题**（已标注不需要的功能）：
- 当前句子文本 → ❌ 文本中已有高亮显示
- 播放状态文字「第X段·第Y句」→ ❌ 文本中已有高亮
- 句子级跳转按钮（上/下一句、上/下一段）→ ❌ 双击文本播放，双击高亮文本停止
- 底部栏中的角色按钮 → ❌ 右上角已有角色菜单入口

**修改后结构：**

```
┌─ 朗读模式下底部栏（audioBottomBar）新结构 ────────────────────┐
│  [上一章] ████████████░░░░░ [下一章]                          │
│                                                               │
│  ┌──────────── 简洁控制行 ────────────────────────┐           │
│  │  [⏮]  [▶/⏸]  [⏭]   队列:N    [□x]语速 [□xdB] │           │
│  └────────────────────────────────────────────────┘           │
│                                                               │
│  [目录] [设置齿轮] [字体]                                     │
└────────────────────────────────────────────────────────────┘

说明：
- ⏮ 跳转到章节开头
- ▶/⏸ 播放/暂停
- ⏭ 跳转到下一段落
- 队列:N 显示待播放数
- 语速/音量：文字标签显示当前值，点击展开 Popover 滑块
- 角色入口：屏幕右上角已有（header 中 person.2 图标），底部不重复
```

### 沉浸模式浮动控制

```
         ╭──────────────╮
         │     ▶/⏸      │   ← 大圆按钮，仅播放/暂停
         ╰──────────────╯
         屏幕右侧浮动，沉浸模式下可见
         不再包含段落/句子跳转按钮（双击文本即可）
```

### 角色面板（替换 `characterPanelSheet`）

角色持久化到 `UserDefaults`（通过 `ReaderStore.saveState()` / `loadState()`），排序规则：
- 旁白（narrator）始终在第一位
- 其余角色按本书中**出现次数**降序排列（来自 `CharacterProfile.appearanceCount`，AI Worker 返回时累计）
- 新角色追加到末尾，不打断已有顺序

```
┌─ Sheet: 角色管理 ──────────────────────────────────────┐
│  章节: 《第一章 初到京城》                                │
│  [重新扫描角色] • AI 缓存: ● 已命中 / ○ 未缓存          │
│  ┌──────────────────────────────────────────────────┐   │
│  │ 旁白（默认音色：晓晓）  [更换音色 ▾]              │   │
│  │  第一次朗读时立即使用此音色启动播放                │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  ┌─ 小明 ───── (出现 47 次) ── [♂] ─── [⋮] ┐          │
│  │  音色：晓晓 (zh-CN-Xiaoxiao)              │          │
│  │  [小晓] [晓萱] [晓伊] ...                  │          │
│  │  别名：明明                                │          │
│  │  合并到... / 分离角色                      │          │
│  └──────────────────────────────────────────┘          │
│  ┌─ 李华 ───── (出现 23 次) ── [♀] ─── [⋮] ┐          │
│  │  ...                                       │          │
│  └──────────────────────────────────────────┘          │
└────────────────────────────────────────────────────────┘
```

### 设置面板 — 新增「朗读设置」Section

```
┌─ 朗读设置 ─────────────────────────────────────────────┐
│  AI 语义分段（关闭=使用本地解析回退）  [Toggle]          │
│  懒加载触发阈值：当前缓冲剩余 [5] 段时预取               │
│                                                          │
│  旁白默认音色: 晓晓  [更换 ▾]                            │
│                                                          │
│  语速： [━━━━━●━━━━━]  +5                               │
│  音量： [━━━●━━━━━━━━]  -2dB                            │
│  段落重叠： [━━●━━━━━━]  80ms                           │
│                                                          │
│  AI Worker 轮询: [启用]                                  │
│  [管理 Worker 列表 →]  (跳转语音引擎页面)                │
│  TTS 自动匹配: [启用]  // 自动选择响应最快的节点          │
│  [管理 TTS 服务器 →]  (跳转语音引擎页面)                 │
└────────────────────────────────────────────────────────┘
```

---

## 四、核心模块划分与复用策略

### 模块 A：Worker 轮询调度器（新增）

**文件：** `WorkerRotator.swift`

```swift
actor WorkerRotator {
    private var configs: [AIWorkerConfig] = []
    private var index = 0
    
    func next() -> AIWorkerConfig? {
        let enabled = configs.filter(\.isEnabled).sorted(by: \.priority)
        guard !enabled.isEmpty else { return configs.first(where: \.isDefault) }
        index = (index + 1) % enabled.count
        return enabled[index]
    }
    
    func markFailure(_ id: UUID) { /* 临时跳过 */ }
    func markSuccess(_ id: UUID) { /* 恢复 */ }
}
```

### 模块 B：投机播放器（新增）

**文件：** `SpeculativePlayer.swift`

```swift
actor SpeculativePlayer {
    /// 用旁白音色快速合成一段文本作为占位
    func synthesizePlaceholder(text: String, narratorVoice: String, serverID: UUID) async -> TTSQueueItem?
    
    /// 真实结果到达后，替换占位
    func replaceWithReal(placeholderID: UUID, realItems: [TTSQueueItem], controller: AdvancedAudioPlaybackController)
}
```

### 模块 C：AI 分段 + 解析缓存（新增）

**文件：** `AIParseCache.swift`

```swift
actor AIParseCache {
    func getCachedSegments(chapter: BookChapter) -> [AISegment]?
    func saveSegments(chapter: BookChapter, segments: [AISegment])
    func invalidate(chapterID: UUID)
    func invalidateAll()
}
```

### 模块 D：懒加载调度器（新增，整合进 ReaderStore）

逻辑内联到 `ReaderStore.playChapterWithAI()`：

```swift
private var parsedSegmentsBuffer: [AISegment] = []
private var currentSliceIndex = 0
private let prefetchThreshold = 5  // 可配置

func playChapterWithAI(chapter: BookChapter, from paragraphIndex: Int) async {
    // 1. 投机启动：旁白合成第一段
    let placeholder = await speculativePlayer.synthesizePlaceholder(...)
    audioController.appendToQueue([placeholder].compactMap { $0 })
    
    // 2. 检查缓存
    if let cached = await cache.getCachedSegments(chapter: chapter) {
        parsedSegmentsBuffer = cached
    } else {
        // 3. 逐片懒加载
        try await requestNextSlice()
    }
    
    // 4. 并发合成所有已解析段
    let items = await synthesizeSegments(parsedSegmentsBuffer)
    audioController.replaceQueue(items)  // 替换投机段
    
    // 5. 播放循环中监听剩余量
    while hasMoreText {
        if (parsedSegmentsBuffer.count - currentPlayIndex) <= prefetchThreshold {
            try await requestNextSlice()
            let newItems = await synthesizeSegments(newSegments)
            audioController.appendToQueue(newItems)
        }
        await Task.yield()
    }
}
```

### 模块 E：角色管理 UI（从 TTSView 抽取）

**来源：** TTSView.`customMultiRoleSection` → `CharacterRoleCard`
- 合并/分离/重命名/删除
- 别名系统
- 音色选择器 `VoicePickerPopover`

### 模块 F：全局 TTS 设置控制（共享 @AppStorage）

**Key 统一：**
- `globalRate` → 语速
- `globalVolume` → 音量
- `globalOverlap` → 重叠
- `narratorVoice` → 旁白默认音色（新增）
- `aiWorkerRotation` → 是否启用 Worker 轮询（新增）
- `aiPrefetchThreshold` → 懒加载阈值（新增）
- `ttsAutoMatch` → 是否启用 TTS 服务器自动匹配（新增）

---

## 五、实施步骤

### 第一步：新增基础设施（无 UI 变更）
1. 创建 `WorkerRotator.swift` — 轮询调度 actor
2. 创建 `AIParseCache.swift` — 缓存 actor（JSON 文件存储）
3. 创建 `SpeculativePlayer.swift` — 投机合成 actor
4. 创建 `AISegmentCacheManager.swift` — 统一缓存管理入口（可选，也可内联）
5. 扩展 `AIWorkerConfig` 模型 — 增加 `isEnabled`、`priority`

### 第二步：抽取通用 UI 组件（从 TTSView 移出）
1. 将 `VoicePickerPopover` 移出 TTSView 到独立文件
2. 将 `CharacterRoleCard` 抽取为独立 View
3. 将 `SynthesisBuffer` 抽取为独立 actor
4. TTSView 中保持 import/引用

### 第三步：改造 ReaderStore 播放流程
1. 新增懒加载状态属性：
   - `parsedSegmentsBuffer: [AISegment]`
   - `currentSliceIndex: Int`
   - `aiParseState: [UUID: AIParseState]`
2. 实现 `playChapterWithAI()`（整合缓存 → 轮询 → 懒加载 → 投机播放）
3. 实现缓存读写逻辑
4. 保留旧 `playChapterStreaming()` 作为回退

### 第四步：精简 ReaderView 底部控制栏
1. 移除句子级跳转按钮（双击文本已有）
2. 移除当前句子文字显示（高亮已有）
3. 简化控制行：⏮ ▶/⏸ ⏭ 队列:N 语速 音量
4. 语速/音量点击弹出 Popover 滑块

### 第五步：替换角色面板
1. 保留右上角 person.2 图标入口
2. 替换 sheet 内容为角色管理 UI（CharacterRoleCard + 别名）
3. 顶部增加旁白默认音色设置
4. 显示 AI 缓存状态

### 第六步：扩展 ReaderSettingsView
1. 新增「朗读设置」Section
2. AI 语义分段开关（回退到本地解析）
3. 旁白默认音色选择器
4. 懒加载阈值设置
5. 语速/音量/重叠滑块
6. Worker 轮询开关

### 第七步：测试与打磨
1. Worker 轮询容错（一个失败自动切下一个）
2. 缓存命中/未命中/重新解析流程
3. 投机播放 → 真实段替换 → 用户无感知
4. 懒加载触发时机
5. 跨章节预取
6. 从中间段落恢复播放（需要重新切片计算偏移）

---

## 六、文件改动清单

| 文件 | 改动类型 | 说明 |
|------|----------|------|
| `WorkerRotator.swift` | **新建** | Worker 轮询调度 actor |
| `AIParseCache.swift` | **新建** | 解析结果缓存 actor |
| `SpeculativePlayer.swift` | **新建** | 投机（旁白预合成）actor |
| `TTSView.swift` | 抽取 | 移出 `VoicePickerPopover`、`CharacterRoleCard`、`SynthesisBuffer` |
| `CharacterRoleCard.swift` | **新建** | 通用角色管理卡片（从 TTSView 抽取） |
| `VoicePickerPopover.swift` | **新建** | 从 TTSView 底部分离 |
| `SynthesisBuffer.swift` | **新建** | 从 TTSView 分离 |
| `AIWorkerConfig.swift` | 修改（或内联） | 增加 `isEnabled`、`priority` |
| `EdgeTTSServerConfig.swift` | 修改（或内联在 EdgeTTSService） | 增加 `lastLatencyMs`、`lastChecked` |
| `ReaderStore.swift` | 修改 | 新增懒加载状态、`playChapterWithAI()`、缓存逻辑 |
| `ReaderView.swift` | 修改 | 精简底部栏、替换角色面板 |
| `ReaderSettingsViews.swift` | 修改 | 新增朗读设置 Section |
| `ReaderSheets.swift` | 修改 | 调整角色面板 sheet 内容 |

## 七、回退方案

保持 AI 功能独立可控：

| 回退层级 | 触发条件 | 行为 |
|----------|----------|------|
| **缓存回退** | 缓存命中 | 零 AI 调用，直接使用历史解析结果 |
| **轮询降级** | 当前 Worker 失败 | `WorkerRotator` 自动切下一个 |
| **本地解析回退** | 用户关闭「AI 语义分段」或所有 Worker 失败 | 回到旧的 `playChapterStreaming()` + `parseDialogueSegments()` |
| **无旁白回退** | 用户未设置旁白音色 | 投机步骤跳过，等待 AI 返回后再开始播放（显示「正在解析...」） |

所有回退对用户透明，通过设置面板 `@AppStorage("readerUseAI")` / `@AppStorage("readerEnableRotation")` 控制。
