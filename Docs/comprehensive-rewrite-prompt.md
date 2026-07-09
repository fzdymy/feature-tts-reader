# FeatureTTSReader — 全面重构 Prompt (v2)

## 🎯 核心决定: 废弃 CosyVoice 3.0，全面转向 Edge TTS

**原因:**
- CosyVoice 3.0 在 LiveContainer 下因 ANE entitlement 缺失只能跑 CPU，10-30s/句，1.2GB 下载 + 1.8GB RAM 撞 2GB 上限，`os_proc_available_memory()` 返回 0 阻塞启动
- 1278 行模型管理代码（下载/解压/验证/CAM++/缓存/memory check）消耗 ~50% 维护精力
- Edge TTS 内置音色已满足本项目多角色需求
- 未来若有声纹克隆需求，可在 Edge TTS relay 服务端接入其他 TTS API，无需修改客户端

## 项目背景
iOS 18+ SwiftUI 多角色 TTS 朗读器。通过 HTTP 流式合成到局域网 Edge TTS relay 服务器 (FastAPI + edge-tts, 仓库: https://github.com/fzdymy/tts)。LiveContainer 侧载运行。

## 关键约束
- **AVAudioEngine 不可用** — LiveContainer 下 SIGSEGV。全部使用 AVAudioPlayer。
- **MPRemoteCommandCenter 在 LiveContainer 无效** — 锁屏控制不可用，要有运行时检测降级。
- **Edge TTS 是唯一 TTS 引擎** — 零模型下载，~200ms/句，HTTP POST SSML 到局域网服务器
- **服务器可扩展** — relay 服务端可接入任意 TTS 后端 (Edge TTS / OpenAI TTS / CosyVoice API)，客户端无需变更

## 本次重构范围

### 核心变更: 移除 CosyVoiceService (1278 行)，新增 EdgeTTSService

**删除的文件/代码:**
| 删除内容 | 行数 | 说明 |
|----------|------|------|
| `CosyVoiceService.swift` 全部 | ~1278 | 模型下载/解压/验证/CAM++/缓存/变体选择 |
| `CharacterProfile.voiceSampleEmbedding` | ~1 | 声纹数据字段，CosyVoice 专属 |
| `CharacterProfile.voiceSampleURL` | ~1 | 声音样本路径，CosyVoice 专属 |
| `CharacterScanner.defaultVoice()` | ~3 | 永远返回空字符串的死代码 |
| `Store.defaultVoice()` | ~3 | 同上 |
| `Store.refreshVoices()` / `ensureVoiceOptionsLoaded()` | ~10 | Azure TTS 遗留死亡调用链 |
| `VoiceEmbeddingRegistry.swift` | ~77 | 声纹注册表，CosyVoice 专属 |
| `TTSView.swift` 下载管理部分 | ~200 | 模型下载/代理配置/变体选择/手动导入 |
| `Services.swift` 中的旧 AudioPlaybackController | ~200 | 已被 AdvancedAudioPlaybackController 替代 |
| BERT 相关 (BertSpeakerDetector.swift) | ~? | CPU-only BERT 推理，CosyVoice 专属 |

**新增/修改的文件:**
| 文件 | 操作 | 说明 |
|------|------|------|
| `EdgeTTSService.swift` | **新建** | HTTP SSML 客户端，~200 行 |
| `Store.swift` | **大改** | 移除 CosyVoice 引用，简化 playChapterStreaming |
| `TTSView.swift` | **重写** | 模型下载 UI → Edge TTS 服务器配置 |
| `CharacterEditorView.swift` | **简化** | 移除声纹克隆 UI，保留样音试听 |
| `DramaDirector.swift` | **保留** | 情绪分析仍用于 SSML emotionTag |
| `AdvancedAudioPlaybackController.swift` | **保留** | 不变，AVAudioPlayer 架构 |
| `CharacterAnalyzer.swift` | **保留** | 角色抽取/情绪分析仍需要 |
| `CharacterScanner.swift` | **简化** | 移除 defaultVoice 调用 |

**修复的 Bug (P0-P2):** 原有 18 个问题中约 10 个因 CosyVoice 删除而自动消失，剩余需修复。

### 用户可见变化
| 变更 | 旧 | 新 |
|------|----|-----|
| TTS 引擎 | CosyVoice 3.0 (on-device, 10-30s/句) | Edge TTS (局域网, ~200ms/句) |
| 模型下载 | 1.2GB，代理加速，进度条 | 无 |
| 音色选择 | 声纹克隆 (10秒音频样本) | Edge TTS 内置音色 (SSML voice 标签) |
| 服务器配置 | 下载代理 URL | Edge TTS 服务器 URL |
| 缓存 | 磁盘 LRU (SHA256 key) | 服务器端缓存，客户端轻量内存缓存 |
| Docker | 无 | Edge TTS relay 服务器 Docker 部署 |

---

## 整体架构与数据流

### 用户操作流程

```
小说文本
  │
  ├─ [1] 导入 (文件导入 / 文本粘贴)
  │    └─ DocumentImporter → Book 模型 (bookID, text, title)
  │
  ├─ [2] 章节提取 (extractChapters)
  │    └─ 正则检测 "第X章" → 生成 [BookChapter]
  │        └─ 无章节标记 → splitIntoPseudoChapters (每5000字一章)
  │
  ├─ [3] 角色扫描 (scanCharacters) ─── 用户触发 或 自动
  │    └─ CharacterScanner.scan()
  │         ├─ Phase 1: extractCandidates ─ 段落级粗筛 + 3合并正则 + looksLikeRealName
  │         ├─ Phase 2: countCharacterFrequencies ─ AC自动机 O(n) 全文扫描
  │         ├─ prefix-dedup + resolveAliases 去重
  │         └─ Phase 3: estimateAttributes ─ 多段落全局投票 → [CharacterProfile]
  │
  ├─ [4] 构建对话块 (buildDialogueBlocks)
  │    └─ 按引号段落合并 → 连续对话段落合并为一个块, 2个无引号段落打断
  │
├─ [5] DramaDirector 前瞻扫描 (第一遍)
│    └─ 遍历所有 blocks/sentences → 构建 allUpcomingSentenceContexts
│         └─ parseDialogueSegments 识别说话者 + emotionTag
│
├─ [6] 合成管线 (TaskGroup + AsyncStream)
│    ├─ 遍历 blocks/sentences
│    │     ├─ parseDialogueSegments → speaker + emotionTag
│    │     ├─ DramaDirector.contextualize → 情绪平滑
│    │     └─ 投递到 TaskGroup (maxConcurrent: 3)
│    ├─ TaskGroup 子任务:
│    │     ├─ 根据 speaker 查角色→音色映射表 (CharacterProfile.voiceID)
│    │     ├─ EdgeTTSService.synthesize(text, speaker, emotionTag)
│    │     │    ├─ buildSSML → HTTP POST → 服务器 → WAV Data
│    │     │    └─ 内存缓存 (可选)
│    │     └─ 返回 TTSQueueItem (含 audioURL + PlaybackAnchor)
│    └─ AsyncStream consumer:
│          ├─ 首个 item → audioController.playQueue (立即播放)
│          └─ 后续 items → audioController.appendToQueue (预加载)
│
└─ [7] 播放完成等待
       └─ withCheckedContinuation + $isPlaying.dropFirst().filter{!$0}
            → 清理临时音频文件 → isBusy = false
```

### 核心数据模型关系

```
Book ── hasMany ── BookChapter
                      │
                      ├── text: String (章节全文)
                      ├── title: String
                      └── paragraphs: [String] (按 \n\n 分割)

CharacterProfile
    ├── id: UUID
    ├── name: String (规范名, e.g. "萧炎")
    ├── aliases: [String] (e.g. ["炎帝", "萧炎哥哥"])
    ├── voiceSampleEmbedding: Data? (JSON [Float], 192维 CAM++ 声纹)
    ├── voiceSampleURL: URL? (WAV 样本文件路径)
    ├── isNarrator: Bool
    ├── gender/age/tone: String (来自 estimateAttributes 全局投票)
    └── rate/pitch/style: Int (CosyVoice 参数, Azure 遗留)

TTSQueueItem
    ├── id: UUID
    ├── segment: ScriptSegment (characterName, text, paragraphIndex)
    ├── audioURL: URL (写入磁盘的 WAV 文件)
    ├── anchor: PlaybackAnchor (跨栈同步锚点)
    ├── paragraphIndex, sentenceIndex: Int
    ├── chapterTitle, bookTitle: String
    └── chapterIndex: Int

PlaybackAnchor
    ├── bookID, chapterIndex: Int
    ├── paragraphIndex, sentenceIndex: Int
    └── speakerID: UUID?

VoiceEmbeddingRegistry (actor)
    ├── register(canonicalName:embedding:sampleRate:source:)
    ├── registerAliases(aliases:for:)
    ├── cacheKey(for:) → SHA256(text + emotionTag + embedding hash)
    └── resolveAlias(_:) → canonicalName

DramaDirector (@MainActor)
    ├── contextualize(_:context:) → refined SentenceUnit
    └── SentenceContext (text, speakerID, emotionTag, isNarrator, ...)
```

---

## 多角色自动识别匹配逻辑

### 核心问题
小说文本中，"谁说的这句话" 必须从自然语言中推断。无标签、无元数据。系统通过 **三级推断链** 实现:

### 第一级: 角色抽取 (静态分析)

**文件: `CharacterScanner.swift` + `CharacterAnalyzer.swift`**

当用户点击"扫描角色" (或 `scanCharacters()` 自动触发) 时执行:

```
输入: 全文 text (可能 10000万+ 字)

Phase 1: extractCandidates (段落级粗筛)
  对每个段落:
    guard 含 "说/道/「/」/“/”" 等对话特征
  → 3个合并正则:
    speakerPattern: "[\u{4e00}-\u{9fff}]{2,4}[说|道|笑道|...]"
    titlePattern:   "[\u{4e00}-\u{9fff}]{2,4}(先生|小姐|姑娘|公子|...)」
    actionPattern:  "[说|道|问|喊|叫]\u{201C}|\u{300C}"
  → looksLikeRealName 静态规则链 (reject 卫生间/尤其是 等假阳性)
  → NLTagger 上下文验证 (放行网文名如萧炎/林动)
  输出: Set<String> 高置信度候选人 (如 ["陈煜", "慕雪", "林动", "萧炎"])

Phase 2: countCharacterFrequencies (AC自动机)
  一次建树 (Aho-Corasick) → O(n) 扫描全文本
  filter: 频率 ≤ 1 的丢弃 (大概率假阳性)
  输出: [String: Int] (e.g. ["陈煜": 342, "慕雪": 128, "卫生间": 0])

去重 & 别名解析:
  1. prefix-dedup: "陈煜" 和 "陈煜道" → 保留短名
  2. resolveAliases: 使用别名规则合并 (从上下文/Zelin 规则推导)
  输出: 去重后的命名列表

Phase 3: estimateAttributes (多段落全局投票)
  对每个角色名:
    收集所有含该角色名的段落
    显式称谓权重 +3 (如 "陈煜笑道")
    代词信号 +1 (如 "他说" 附近的角色名)
    年龄关键词 (如 "老"→老年, "小"/"姑娘"→青年)
    语气关键词 (温柔/冷声→tone 推断)
  弱信号时返回 "未知"/"平稳"
  输出: CharacterAttributes(gender/age/tone/style/rate/pitch)
```

**角色抽取的 guard 机制:**
- 不在每段落前执行 NLTagger 验证 (旧架构: 字符串强匹配误杀网文人名)
- `nonNamePhrases` 硬编码排除 100+ 个已知假阳性 (卫生间/高跟鞋/忍不住等)
- `strongRejectChars` 排除含代词/疑问词的 2-3 字串
- `titleSuffixes` (先生/小姐/掌门等) 用于 titlePattern 正则放行

### 第二级: 对话块构建 (段落分组)

**文件: `Store.swift` `buildDialogueBlocks()`**

```
输入: [String] (按 \n\n 分割的段落)

逻辑:
  遍历段落, 每当检测到含引号段落:
    → 开启新 block
    → 向前合并后续段落直到 2 个连续无引号段落
    → 尾部回退 (不从 block 截断叙述段)

输出: [(texts: [String], globalStart: Int)]

作用: 将相关对话和上下文捆在一起, 确保跨段落说话者跟踪不中断。
例子:
  "陈煜道：「我们走吧。」"  ← 有引号, open block
  "慕雪点点头。"          ← 无引号, 属于同一场景, 保留
  "两人走出院子。"        ← 第2个无引号, close block
```

### 第三级: 说话者推断 (动态运行时)

**文件: `Store.swift` `parseDialogueSegments()` + `detectSpeakerInContext()` + `detectSpeakerAfterQuote()`**

每个句子合成前执行:

```
parseDialogueSegments(in: paragraph, characters: [], lastSpeaker: previousSpeaker)
  │
  ├─ 扫描段落中的引号对 (支持»\u{300C}」「\u{201C}"\u{201D}"\u{2018}'\u{2019}'\u{300E}」\u{300F}「)
  │
  ├─ 引号前内容 → 标记为"叙述者"
  │
  ├─ 引号内内容 → [核心: 说话者推断]
  │    │
  │    ├─ (A) BERT 深度语义检测 (主)
  │    │     └─ BertSpeakerDetector.detectSpeaker(context, quote, candidates)
  │    │          ├─ 使用 on-device BERT 模型 Embedding + 余弦相似度
  │    │          ├─ 准确率 ~77%
  │    │          └─ 返回 (name: String?, score: Float)
  │    │
  │    ├─ (B) 正则上下文检测 (备选 + 补充)
  │    │    ├─ detectSpeakerInContext (引号前 100 字符):
  │    │    │     1) [姓名][说/道/笑道/...] 在末尾 → 最高置信度 (如 "陈煜道：「...」")
  │    │    │     2) [姓名]： 在末尾 (如 "陈煜：")
  │    │    │     3) 角色名在上下文末尾 (如 "...找到陈煜「...」")
  │    │    │     4) 角色名在上下文中最先出现的位置
  │    │    │
  │    │    └─ detectSpeakerAfterQuote (引号后 80 字符):
  │    │          1) [说/道/笑道][姓名] 在开头 (如 "「...」道陈煜")
  │    │          2) [姓名][说/道/笑道] 在开头
  │    │          3) 已知角色名在开头
  │    │          4) 角色名在上下文中最先出现的 위치
  │    │
  │    ├─ (C) BERT + 正则 融合决策:
  │    │     BERT > 0.7     → 直接采用 BERT
  │    │     BERT > 0.5 + 正则匹配 → 采用正则
  │    │     BERT > 0.5     → 采用 BERT
  │    │     正则匹配       → 采用正则
  │    │     BERT > 0.4     → 采用 BERT
  │    │     
  │    │
  │    └─ (D) 呼格检测 (vocative, 前序均失败时):
  │          └─ 引号开头是否含 "姓名，" 或 "姓名," → speaker = 姓名
  │              如: "陈煜，你站住！" → speaker = 陈煜
  │          
  │
  ├─ 推断结果:
  │     speaker = resolvedSpeaker ?? currentLastSpeaker ?? narratorName
  │
  └─ 情绪分析:
        toneAnalyzer.analyzeSentenceTone(quoteText)
          ├─ 检查 ! + ？组合 ("你怎么敢？！" → angry)
          ├─ 检查 ! → angry
          ├─ 检查 ？→ questioning
          ├─ 检查 ...→ hesitant
          ├─ 语气关键词 (温柔/冷声/颤声)
          └─ mapToneToEmotionTag → CosyVoice emotionTag (angry/happy/sad/nil)
```

**说话者跟踪的跨句子状态:**
```
currentLastSpeaker 在 parseDialogueSegments 中逐句更新:
  - 每检测到一个非叙述者的说话者 → currentLastSpeaker = speaker
  - 用于后续未找到明确说话者的句子
  - 跨 block 时通过 lastSpeaker 参数传递 (Store.playChapterStreaming line 1342)
```

### 情绪分析详细逻辑

**文件: `CharacterAnalyzer.analyzeSentenceTone`**

```
输入: 句子文本
输出: ToneResult(style, pitchAdjust, rateAdjust)

规则:
  1. 检查强烈情感标记:
     - "？！" 或 "！？" 组合 → angry (pitch +1, rate +1)
     - 单独 "！" → angry (pitch +1, rate +1)
     - "？" > 3 个 → excited (pitch +1, rate +1)
     - "..." 或 "…" → hesitant (pitch -1, rate -2)
     - "～" 或 "~" → gentle (pitch 0, rate -1)
     
  2. 检查语气关键词 (权重高):
     - toneKeywords: 温柔/轻柔/低声 → gentle
     - angryKeywords: 怒/吼/骂/冷声/厉声 → angry
     - sadKeywords: 哭/泣/哽咽/颤声 → sad
     - happyKeywords: 笑/高兴/开心 → happy
     
  3. 映射到 CosyVoice emotionTag:
     - angry → "angry"
     - cheerful → "happy"  
     - sad → "sad"
     - 其他 → nil (不传递 emotionTag)
```

### 别名解析 (alias → canonical)

**每个 `CharacterProfile` 含 `aliases: [String]`。**

别名来源:
- `resolveAliases()` 自动推导: 使用 Zelin 规则 (核心角色名的简称/尊称映射)
- 用户手动编辑: CharacterEditorView 中设置

别名在管线中的使用:
```
playChapterStreaming 中:
  1. registry.registerAliases(aliases, for: canonicalName)
  2. parseDialogueSegments:
       canonical = characters.first(where: { $0.name == speaker || $0.aliases.contains(speaker) })?.name ?? speaker
  3. cosySegments 构建时确保使用 canonicalName 而非 alias → 避免声纹查找失败
```

---

## 主要文件职责与调用关系

```
┌──────────────────────────────────────────────────────────────┐
│ FeatureTTSReaderApp.swift (App 入口)                         │
│  │ @main struct FeatureTTSReaderApp: App                     │
│  │   body → WindowGroup → ContentView (TabView: Bookshelf/   │
│  │           TTS/Settings)                                   │
├──────────────────────────────────────────────────────────────┤
│ BookshelfView.swift (书架视图)                                │
│  │ → BookDetailView → ReaderView (主阅读界面)                │
│  │ → CharacterListView → CharacterEditorView                 │
│  │ → CharacterAssignmentView                                 │
│  │ → ChapterListView                                         │
├──────────────────────────────────────────────────────────────┤
│ ReaderView.swift (阅读 + 播放控制)                            │
│  │  主要职责:                                                │
│  │  - 显示文本, 逐句高亮 (currentParagraphIndex +            │
│  │    currentSentenceIndex)                                  │
│  │  - 单击句子播放, 双击选中, 滚动同步                       │
│  │  - startPlayback() → store.startPlaybackTask()            │
│  │  - 播放按钮 (播放/暂停/上一句/下一句/上一段/下一段)      │
│  │  - 字号/字体/主题设置                                     │
├──────────────────────────────────────────────────────────────┤
│ Store.swift (核心控制器, ~2181 行)                            │
│  │  class ReaderStore: ObservableObject                      │
│  │  主要职责:                                                │
│  │  ├─ 状态管理: @Published properties (characters,         │
│  │  │  chapters, paragraphs, currentParagraphIndex, 等)      │
│  │  ├─ 章节管理: extractChapters, splitIntoPseudoChapters    │
│  │  ├─ 角色扫描: scanCharacters() → CharacterScanner.scan() │
│  │  ├─ 脚本构建: buildScript() → createScriptSegments()     │
│  │  ├─ 对话解析: buildDialogueBlocks + parseDialogueSegments│
│  │  ├─ 合成管线: playChapterStreaming (TaskGroup+AsyncStream)│
│  │  ├─ 播放控制: startPlaybackTask, stopPlayback,           │
│  │  │           immediateInterruptAndSeek                    │
│  │  ├─ 下载管理: CosyVoice 模型下载/代理配置                │
│  │  └─ 持久化: saveState / restoreState                     │
├──────────────────────────────────────────────────────────────┤
│ CosyVoiceService.swift (合成 actor, ~1278 行)                │
│  │  actor CosyVoiceService                                   │
│  │  主要职责:                                                │
│  │  ├─ 模型下载/安装/验证 (GitHub Releases + 代理)          │
│  │  ├─ CAM++ 声纹注册 (enrollSpeaker)                        │
│  │  ├─ 对话合成 (synthesizeDialogueWithEmbeddings)           │
│  │  │    → DialogueSynthesizer → [Float] → WAV              │
│  │  ├─ 缓存 (NSCache 内存 + 磁盘 LRU, SHA256 key)           │
│  │  ├─ 模型变体选择 (4bit/8bit/bf16)                        │
│  │  └─ 内存检查 (os_proc_available_memory)                  │
├──────────────────────────────────────────────────────────────┤
│ AdvancedAudioPlaybackController.swift (~361 行)              │
│  │  class AdvancedAudioPlaybackController: NSObject          │
│  │  主要职责:                                                │
│  │  ├─ AVAudioPlayer 架构 (非 AVAudioEngine)                │
│  │  ├─ 队列管理: playQueue / appendToQueue / flushPlayback  │
│  │  ├─ 逐句跳过: skipCurrentSentence / skipPreviousSentence │
│  │  ├─ 播放历史: playbackHistory (回退)                     │
│  │  ├─ RMS 音量: averagePower + Timer 轮询                  │
│  │  └─ 播放完成回调: audioPlayerDidFinishPlaying →          │
│  │     playNextSeamlessly                                    │
├──────────────────────────────────────────────────────────────┤
│ CharacterScanner.swift (~130 行)                              │
│  │  struct CharacterScanner                                   │
│  │  scan(text:config:voices:bookID:) → Result                │
│  │  ├─ calls CharacterAnalyzer methods                       │
│  │  ├─ 三阶段管线 (extractCandidates →                      │
│  │  │  countCharacterFrequencies → estimateAttributes)       │
│  │  └─ prefix-dedup + resolveAliases                         │
├──────────────────────────────────────────────────────────────┤
│ CharacterAnalyzer.swift (~1010 行)                            │
│  │  class CharacterAnalyzer                                   │
│  │  └─ 纯逻辑: extractCandidates, countCharacterFrequencies, │
│  │     estimateAttributes, analyzeSentenceTone,              │
│  │     resolveAliases, looksLikeRealName, buildRelationship  │
│  │     Graph, etc.                                            │
├──────────────────────────────────────────────────────────────┤
│ BertSpeakerDetector.swift                                     │
│  │  class BertSpeakerDetector                                 │
│  │  └─ BERT Embedding + 余弦相似度说话者检测                 │
│  │     detectSpeaker(context:quote:candidates:) → (name,score)│
├──────────────────────────────────────────────────────────────┤
│ DramaDirector.swift (~147 行)                                 │
│  │  @MainActor class DramaDirector                            │
│  │  └─ 上下文情绪平滑: contextualize(unit, context)          │
│  │     ├─ 叙述者情绪继承 (从上一个对话角色)                  │
│  │     ├─ 同说话者情绪平滑 (不突变)                          │
│  │     └─ 高潮预判 (上下文窗口 5 句)                         │
├──────────────────────────────────────────────────────────────┤
│ VoiceEmbeddingRegistry.swift (~77 行)                         │
│  │  actor VoiceEmbeddingRegistry                              │
│  │  └─ SHA256 声纹注册表: register / registerAliases /      │
│  │     cacheKey / resolveAlias                                │
├──────────────────────────────────────────────────────────────┤
│ Models.swift (~488 行)                                        │
│  │  Book, BookChapter, CharacterProfile, TTSQueueItem,        │
│  │  ScriptSegment, PlaybackAnchor, VoiceItem (Azure 遗留)    │
├──────────────────────────────────────────────────────────────┤
│ TTSView.swift (~470 行)                                       │
│  │  模型管理: 下载/代理配置/变体选择/手动导入/测试合成       │
├──────────────────────────────────────────────────────────────┤
│ Services.swift (~419 行, 死代码)                              │
│  │  旧 AudioPlaybackController + AsyncSemaphore               │
│  │  当前仅 AsyncSemaphore 被引用                              │
├──────────────────────────────────────────────────────────────┤
│ 其他辅助:                                                    │
│  ├─ TextNormalizer.swift (文本规范化)                        │
│  ├─ DocumentImporter.swift (文件导入)                        │
│  ├─ FontManager.swift + FontManagerView.swift                │
│  ├─ Logger.swift (with log(error:message:) 重载)             │
│  ├─ PersistenceController.swift (UserDefaults 状态持久化)    │
│  ├─ Extensions.swift (Swift 扩展)                            │
│  ├─ ScrollCoordinator.swift                                  │
│  ├─ ReaderSettingsViews.swift + ReaderSheets.swift           │
│  ├─ SettingsView.swift + SettingsView+DataManagement.swift   │
│  └─ BookDetailView.swift, BookshelfGridCard.swift,           │
│     BookshelfListRow.swift, CharacterQuickAddViews.swift,    │
│     TextReaderView.swift                                     │
└──────────────────────────────────────────────────────────────┘
```

---

## ⚠️ 因废弃 CosyVoice 自动解决的 Bug

以下 P0-P2 问题涉及的代码已被删除，无需修复：

| Bug | 原因 |
|-----|------|
| P0-1 模型下载/安装/加载崩溃 | `CosyVoiceService.swift` 删除 |
| P0-2 角色声纹管线无效 | `voiceSampleEmbedding/voiceSampleURL` 字段删除 |
| P0-7 缓存不一致 | `CosyVoiceService` 缓存删除 |
| P1-4 synthesisProgress 线程安全 | `synthesisProgress` 删除 |
| P1-6 progressTask 生命周期 | `progressTask` 删除 |
| P2-1 defaultVoice/reloadVoice 死代码 | 所有相关文件删除 |
| P2-4 checkAvailableMemory | `CosyVoiceService.swift` 删除 |

---

## P0-1 (原 P0-3): skipPreviousSentence 逻辑完全错误 (CRITICAL)

### 问题
`AdvancedAudioPlaybackController.skipPreviousSentence()` (行 179-199) 从 `playbackHistory` 取出 item 插入 queue 开头。但：(1) 当前播放的 item 没有进 history；(2) 连续点击"上一句"只回退一次。

此外 `skipForward`/`skipBackward`/`playPrevious` (行 174-177) 调用 `flushPlayback()` 清空一切，完全没有回退语义。

### 修复要求

**文件: `AdvancedAudioPlaybackController.swift`**

```swift
func skipPreviousSentence() {
    guard let anchor = currentAnchor else { return }
    // 1. 把当前 item（如果存在）放回 queue 的开头（不丢失当前播放位置）
    // 2. 从 history 中找到上一个句子的 item
    // 3. 停止当前播放
    // 4. 将目标 item 插入 queue 开头
    // 5. 立即播放
}

func skipCurrentSentence() {
    // 跳过当前句子：将当前 item 添加到 playbackHistory
    // 然后调用 playNextSeamlessly()
    // (这已经是正确的——但缺少将当前 item 加入 history)
}

func skipPreviousParagraph() {
    // 同上：找到上一个段落的 item
}

func skipCurrentParagraph() {
    // 跳过整个段落到下一段第一句
}
```

关键改动：
1. 在 `playNextSeamlessly` 中，**将当前播放的 `currentItem`** 追加到 `playbackHistory`（而不是在移出 queue 后才加）
2. `skipPreviousSentence`：把当前 `currentItem` 放回 queue 头部，再从 history 取出上一个
3. `skipPreviousParagraph`：同上，但找段落边界
4. 限制 `playbackHistory` 最大 100 项（移除最老的）
5. `playPrevious()` 和 `skipBackward()` 应该调用 `skipPreviousSentence()`，不是 `flushPlayback()`

---

## P0-4: ReaderView 双击/单击冲突 + 过度滚动 (HIGH)

### 问题
**A. 双击冲突** (行 1460-1473)：句子同时有 `.onTapGesture`（单击选中）和 `.onTapGesture(count: 2)`（双击播放）。SwiftUI 中双击会先触发单击事件（延迟 0.3s），导致双击时先选中句子、滚动一次、再触发播放、再滚动一次。用户体验极差。

**B. 滚动风暴** (行 1344-1354)：每次 `currentParagraphIndex` 或 `currentSentenceIndex` 变化都触发自动滚动。快速连播时触发动画累积。

### 修复要求

**文件: `ReaderView.swift`**

**A. 合并手势：** 删除 `.onTapGesture(count: 2)`。改为：
- 单击：选中句子（无跳转播放）
- 长按 + 拖动：文本选择（已有 `.textSelection(.enabled)`）
- 双击：`selectSentence` + 触发播放。用 `DispatchQueue.main.asyncAfter` 区分单击/双击：

```swift
// 不直接用 .onTapGesture(count: 2)，改为自定义手势识别
// 或者直接用单次点击做播放（用户最自然的期望：点击句子就从这里读）
```

推荐方案：**单击句子直接开始播放**（这就是大多数听书 app 的行为）。删除 `selectSentence` 的滚动逻辑。

**B. 防抖：** 在 `updateAutoScrollForCurrentPlayback()` 中：
```swift
private var lastScrollRequest: Date = .distantPast
private func updateAutoScrollForCurrentPlayback() {
    let now = Date()
    guard now.timeIntervalSince(lastScrollRequest) > 0.3 else { return }  // 300ms 防抖
    lastScrollRequest = now
    // ...原有滚动逻辑
}
```

---

## P0-5: 第一章播放后卡死 (HIGH)

### 问题
`playChapterStreaming` 的 `withCheckedContinuation` 等待播放完成（行 1477-1483）。但如果所有合成都失败（`consumed == 0` 已处理），或者播放器队列清空但 `isPlaying` 未正确触发 `.dropFirst()`，`continuation` 永远不 resume。用户无法第二次点击播放。

### 修复要求

**文件: `Store.swift`**

为 `withCheckedContinuation` 添加超时：

```swift
await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
    if !audioController.isPlaying { cont.resume(); return }
    let timeoutTask = Task {
        try? await Task.sleep(nanoseconds: 3 * 1_000_000_000) // 3s 超时兜底
        cont.resume()
    }
    let c = audioController.$isPlaying
        .dropFirst().filter { !$0 }.first()
        .sink { _ in cont.resume() }
    playbackContinuationCancellable = c
}
// 记得取消 timeoutTask 在正常路径上
```

---

## P0-6: startPlaybackTask 中重复的 scanCharacters 调用 (HIGH)

### 问题
`ReaderView.startPlayback()` (行 1356-1373) 调用了 `store.scanCharacters()` 和 `store.buildScript()`。但 `playChapterStreaming`（在 `startPlaybackTask` 内部调用）会**再次**扫描角色和构建对话块。两遍扫描是对同一文本的完全重复。

对于 50000 字的小说，角色扫描 ~500ms，对话解析 ~200ms，两遍就是 1.4s 的浪费时间。

### 修复要求

**文件: `ReaderView.swift`** (行 1356-1373)

删除 `scanCharacters` 和 `buildScript` 调用。只保留：
```swift
store.audioController.playbackRate = Float(playbackSpeed)
store.startPlaybackTask(chapter: chapter, fromParagraphIndex: fromParagraphIndex)
```

---

## P0-7: 合成本地和远程缓存不一致 (HIGH)

### 问题
`CosyVoiceService` 的 `synthesizeDialogueWithEmbeddings` 使用 `cachedAudio()` / `storeCache()` 做内存+磁盘缓存。但 `VoiceEmbeddingRegistry` 的 SHA256 缓存键是**按 speaker 名计算的**。如果两个角色同名但不同 embedding（切换样本后），缓存键不变，返回旧 embedding 的合成音频。

### 修复要求
`CosyVoiceService.swift` 中，在 `synthesizeDialogueWithEmbeddings` 计算缓存键时，**embedding 内容变化必须使缓存失效**：
```swift
// 当前：只用 speaker 名
// 改为：连接 speaker 名 + embedding hash
```

具体：`registry.cacheKey(for:spk:text:emotionTag:)` 已经包含 embedding hash（行 937-938）。确保 `cachedAudio(key:)` 的 key 使用了这个 hash 值。当前代码：
```
key = cacheKey(text: "dialogue:\(segmentText)|registry:\(speakerParts.joined(separator: ","))", embedding: nil)
```
这里 `speakerParts` 已经是 `registry.cacheKey()` 的结果（包含 hash），理论没问题。但需要确认 `registry.cacheKey()` 的 hash 确实随 embedding 变化而变化。

---

## P0-8: TTSQueueItem decode 后 UUID 丢失 (HIGH)

### 问题
`TTSQueueItem` (Models.swift 行 230-247) 有 `let id = UUID()` 但 `CodingKeys` 不包含 `id`。decode 后每次得到新 UUID。如果其他地方用 ID 匹配，会失败。

### 修复
在 `CodingKeys` 中添加 `case id` 同时把 `id` 改为 `var` 或使用默认值 decode。

---

## P1-1: playChapterStreaming 中 TaskGroup 内 fallback 行程竞态 (HIGH)

### 问题
`playChapterStreaming` (Store.swift ~行 1399-1413) 在 `TaskGroup` 子任务中合成失败时调用 `playLocalSpeech(sentence)`。但 `playLocalSpeech` 内部调用 `stopPlayback()` 取消 `playbackTask`——执行合成代码的**就是这个** `playbackTask`。这会触发 `playbackTask.cancel()` → TaskGroup 子任务抛出 `CancellationError` → 不可预知行为。

此外行 1407 的 `as? TTSError == .timeout` 是错误 Swift 模式匹配，应使用 `if let ttsError = error as? TTSError, ttsError == .timeout`。

### 修复要求

**文件: `Store.swift`** (行 ~1399-1413)

```swift
// 当前：
// TaskGroup 子任务中直接调用 playLocalSpeech
// 改为：子任务只返回 fallback 标记，不要在子任务中调用 playLocalSpeech

// 在 TaskGroup 外部的 consumer 循环中处理 fallback：
for await item in stream {
    if let item = item {
        // 正常合成 item → 入队
    } else {
        // 合成失败 → 在主消费循环中调用 playLocalSpeech，不触发 playbackTask 取消
    }
}
```

同时修复行 ~1407 的模式匹配：
```swift
// 旧：error as? TTSError == .timeout
// 新：
if let ttsError = error as? TTSError, ttsError == .timeout {
    // 超时处理
}
```

---

## P1-2: playbackHistory 无上限导致内存泄漏 (HIGH)

### 问题
`AdvancedAudioPlaybackController.playbackHistory` (行 18, 108) 无限增长。用户播放 10000 句后，数组持有 10000 个 `TTSQueueItem` 引用，每个包含 `audioURL` (Data 或 URL)，可能占用数百 MB。

### 修复要求

**文件: `AdvancedAudioPlaybackController.swift`**

```swift
// 行 108：在 append 后添加上限
playbackHistory.append(currentItem)
if playbackHistory.count > 100 {
    playbackHistory.removeFirst(playbackHistory.count - 100)
}
```

---

## P1-3: fromParagraph → fromParagraphIndex 转换使用文本匹配，脆弱＋歧义 (HIGH)

### 问题
`Store.playFromParagraph()` (行 ~1948-1974) 的 `paragraphIndex(for:in:)` 使用文本子串匹配 (`$0.contains(trimmed) || trimmed.contains($0)`)。两段含相同文本时，`firstIndex` 返回错误段落。空 `trimmed` 使 `fromParagraphIndex` 为 `nil`，从头播放。

### 修复要求

**文件: `Store.swift`** (行 ~1948-1974)

将 `paragraphIndex(for:in:)` 改为精确段落索引传递，不再依赖文本匹配。如果调用者已知段落索引，直接传递索引而非文本：

```swift
// 新增方法
func playFromParagraphIndex(_ paragraphIndex: Int, in chapter: BookChapter) {
    // 直接使用索引，不经过文本匹配
    Task {
        await startPlaybackTask(chapter: chapter, fromParagraphIndex: paragraphIndex)
    }
}

// 废弃 playFromParagraph 或改为索引重载
```

---

## P1-4: synthesisProgress 是 nonisolated(unsafe) 全局状态但在 TaskGroup 中共享 (HIGH)

### 问题
`CosyVoiceService.synthesisProgress` (行 91) 是 `nonisolated(unsafe) var`。`playChapterStreaming` 的 `progressTask` (行 ~1386-1397) 每 200ms 轮询这个值。但当 `TaskGroup` 中 3 个合成任务并发时，该值不能区分属于哪个任务——进度可能跳变。

此外 `progressTask` 在 `defer { progressTask.cancel() }` (行 ~1397) 中随 sync 闭包返回取消。如果合成抛出异常（行 ~1406），`progressTask` 被取消时 fallback 播放尚未开始。

### 修复要求

**文件: `Store.swift`** + `CosyVoiceService.swift`

选项 A（推荐）：将 `synthesisProgress` 改为按任务隔离，不在 actor 级别共享：
```swift
// CosyVoiceService.swift
// 删除 nonisolated(unsafe) var synthesisProgress
// 改为每个合成请求使用 TaskLocal 或返回进度 AsyncStream
```

选项 B（轻量）：`progressTask` 的 `defer` 改为只在上层 consumer loop 结束时取消：
```swift
// 不放在 synthesis closure 的 defer 中
// 放在 consumer loop 结束后（asyncStream 迭代完）
```

---

## P1-5: cancelPlaybackTaskAndWait 的 TOCTOU 竞态 (HIGH)

### 问题
`cancelPlaybackTaskAndWait()` (行 ~1121-1125) 中，`playbackTask?.cancel()` 和 `try? await playbackTask?.value` 之间，另一线程可能设置新的 `playbackTask`（来自 `startPlaybackTask` 或 `immediateInterruptAndSeek`）。`await` 将等待新任务而非已取消的任务。

### 修复要求

**文件: `Store.swift`** (行 ~1121-1125)

```swift
private func cancelPlaybackTaskAndWait() async {
    let task = playbackTask
    playbackTask = nil  // 清空引用，防止后续代码误用
    task?.cancel()
    _ = try? await task?.value
}
```

---

## P1-6: progressTask 在 TaskGroup 内合成失败后仍存活 (MEDIUM)

### 问题
`progressTask` 在合成 closure 的 `defer` 中取消。但 TaskGroup 的 `addTask` 块中合成异常导致 `defer` 执行时，该任务已因 `TaskGroup` 的 `cancelAll` 被隐式取消。`progressTask.cancel()` 无效果，但 `defer` 有副作用的代码仍执行。更严重的是，`progressTask` 的 Actor 捕获 (`CosyVoiceService.shared`) 导致 Actor 在短暂锁定期间保持。

### 修复要求

**文件: `Store.swift`** (行 ~1386-1397)

```swift
// 将 progressTask 移到 consumer 循环层级，不在 per-item closure 中创建
let progressTask = Task { [weak store] in
    guard let store else { return }
    while !Task.isCancelled {
        let progress = await CosyVoiceService.shared.synthesisProgress
        if progress > 0 {
            await MainActor.run {
                store.ttsProgressMessage = "合成中... \(Int(progress * 100))%"
            }
        }
        if progress >= 1.0 { break }
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms 代替 200ms
    }
}
// 在 consumer loop 结束后（asyncStream 迭代完毕）取消
defer { progressTask.cancel() }
```

---

## P2-1: defaultVoice() / reloadVoice() / refreshVoices() 死代码 (MEDIUM)

### 问题
- `Store.defaultVoice(for:tone:role:name:voices:)` (行 ~2142-2144) 永远返回 `""`，但在 5 个位置被调用，所有角色 `voice` 属性为 `""`。
- `CharacterScanner.defaultVoice(for:voices:)` (行 ~127-129) 同样返回 `""`。
- `Store.refreshVoices()` (行 ~990-992) 设置 `voices = []`，从不加载任何数据。`ensureVoiceOptionsLoaded()` 调用它形成空循环。

这些代码是旧 Azure TTS 架构遗留，对 CosyVoice 完全无效。

### 修复要求

**文件: `Store.swift` + `CharacterScanner.swift`**

```swift
// Store.swift: 删除或标记废弃 defaultVoice() 
// 将所有调用处的 defaultVoice(...) 替换为 ""
// 或将整个方法标记为 @available(*, deprecated)

// Store.swift ~990-992: 将 refreshVoices 改为空实现
func refreshVoices() {}
```

---

## P2-2: scanCharacters 多重冗余调用导致性能浪费 (MEDIUM)

### 问题
`scanCharacters()` 在 9+ 个位置被调用。关键双重扫描路径：

1. `ReaderView.startPlayback()` (行 ~1367): 调用 `store.scanCharacters()` 
2. 然后同一方法 (行 ~1370) 调用 `buildScript()`，`buildScript` 内部 (Store 行 ~964) 又检查 `characters.isEmpty` → 调用 `scanCharacters()` 第二遍。

3. `CharacterAssignmentView` (行 ~241-386) 有**完全独立**的内联扫描管线实现，不调用 `CharacterScanner.scan()`。

### 修复要求

**文件: `ReaderView.swift` + `Store.swift` + `CharacterAssignmentView.swift`**

**ReaderView.startPlayback():**
```swift
// 删除行 ~1367: await store.scanCharacters()
// buildScript 内部会自行检查并扫描
```

**Store.buildScript():**
```swift
// 将 buildScript 的扫描 guard 改为不冗余扫描
// 如果调用方已保证 characters 非空，跳过 scanCharacters
```

**CharacterAssignmentView:**
```swift
// 替换行 ~241-386 的内联扫描为调用 CharacterScanner.scan()
// 删除 ~150 行重复代码
```

---

## 更新: `CharacterAssignmentView` (行 ~241-386) 内联扫描管线替换

### 问题
`CharacterAssignmentView` 包含 ~145 行内联的三阶段扫描实现 (extractCandidates → countCharacterFrequencies → estimateAttributes)，完全独立于 `Store.swift` 和 `CharacterScanner.swift` 中的共享管线。这导致：
1. 同一扫描逻辑有两份实现，后续维护需要同步修改两处
2. 内联代码使用了不同的启发式参数，可能导致角色扫描结果不一致
3. 代码膨胀，增加编译时间和维护负担

### 修复要求

**文件: `CharacterAssignmentView.swift`** (行 ~241-386)

替换整个内联扫描实现为调用 `CharacterScanner.scan()`：

```swift
// 删除行 241-386 的整个内联实现：
// private func startScan() async {
//     // 三阶段管线：~145 行
// }
//
// 改为：
func startScan() async {
    guard let bookText = store.bookText else { return }
    let scanner = CharacterScanner()
    let characters = await scanner.scan(from: bookText, bookID: store.currentBookID)

    // 如果已有角色，合并（不覆盖现有 embedding/样本）
    var merged = characters
    for existing in store.characters {
        if merged.first(where: { $0.canonicalName == existing.canonicalName }) == nil {
            merged.append(existing)
        }
    }
    store.characters = merged

    // 触发 UI 更新
    isLoading = false
}
```

简化: `CharacterAssignmentView` 不再维护自己的扫描管线和 `CharacterScanner.voices` 静态属性，统一使用 `CharacterScanner.scan()`。

---

## P2-3: isParagraphReading 没有对应的 isSentenceReading 辅助函数 (MEDIUM)

### 问题
`ReaderView.swift` (行 ~1478-1481) 定义了 `isParagraphReading()` 函数，但对应的高亮逻辑在行 ~1432 使用内联 `store.currentParagraphIndex == pi && store.currentSentenceIndex == si`，不重用辅助函数。代码不一致。

### 修复要求

**文件: `ReaderView.swift`**

```swift
// 添加辅助函数：
private func isSentenceReading(pi: Int, si: Int, isCurrentChapter: Bool) -> Bool {
    guard isCurrentChapter else { return false }
    return store.currentParagraphIndex == pi && store.currentSentenceIndex == si
}

// 行 ~1432 的高亮改用此函数：
let isHighlighted = isSentenceReading(pi: pi, si: si, isCurrentChapter: isCurrentChapter)
```

---

## P2-4: checkAvailableMemory 仅检查加载前，不检查合成前 (MEDIUM)

### 问题
`CosyVoiceService.checkAvailableMemory()` 只在 `warmUpModel` (行 ~399) 和 `importModel` (行 ~918) 被调用，都是模型加载前。但模型在加载后可能因内存压力被 OS 驱逐。合成前没有内存检查，可能导致合成中途 OOM。

### 修复要求

**文件: `CosyVoiceService.swift`**

在 `synthesizeDialogueWithEmbeddings` 开始时添加轻量内存检查：
```swift
func synthesizeDialogueWithEmbeddings(...) async throws -> Data {
    // 轻量检查：可用内存低于 200MB 时抛出错误
    let available = os_proc_available_memory()
    if available > 0 && available < 200_000_000 {
        throw TTSError.downloadFailed("合成时内存不足（仅剩 \(available / 1_000_000) MB）")
    }
    // ... 原有合成逻辑
}
```

---

## Edge TTS 实现: 唯一 TTS 引擎

### 架构

```
用户操作
  │
  └─ Store.playChapterStreaming()
       │
       ├─ 角色声纹注册 (已废弃 — 删除)
       ├─ 情绪分析 → emotionTag → SSML
       │    ├─ DramaDirector.contextualize → emotionTag
       │    └─ CharacterAnalyzer.analyzeSentenceTone → style
       │
       ├─ EdgeTTSService.synthesize(...) ← 唯一合成路径
       │    ├─ buildSSML(text, speaker, rate, pitch, emotionTag)
       │    ├─ HTTP POST → {serverURL}/synthesize
       │    │    └─ body: { ssml: "<speak>...</speak>" }
       │    └─ return WAV Data
       │
       ├─ 写入临时文件
       ├─ AdvancedAudioPlaybackController.playQueue
       └─ 播放完成 → cleanup

服务器侧 (Docker):
  fzdymy/tts (FastAPI + edge-tts)
    ├─ POST /synthesize → edge-tts CLI → WAV
    ├─ GET  /health → OK
    └─ 未来可扩展: POST /synthesize-openai /synthesize-cosyvoice-api
```

### 多角色策略

Edge TTS 没有声纹克隆，但 SSML 支持不同 `voice` 标签：
```xml
<speak>
  <voice name="zh-CN-XiaoxiaoNeural"><prosody rate="+32%" pitch="+10%">
  陈煜道：「我们走吧。」
  </prosody></voice>
  <voice name="zh-CN-XiaoyiNeural"><prosody rate="+20%" pitch="+5%">
  「嗯。」慕雪轻声应道。
  </prosody></voice>
  <voice name="zh-CN-YunjianNeural"><prosody rate="0%" pitch="0%">
  叙述者旁白。
  </prosody></voice>
</speak>
```

角色→音色映射表（由用户配置或自动分配）:
| 角色类型 | 推荐 Azure Voice | 性别 |
|----------|-----------------|------|
| 旁白/叙述者 | zh-CN-YunjianNeural | 男 |
| 男主 | zh-CN-YunxiNeural | 男 |
| 女主 | zh-CN-XiaoyiNeural | 女 |
| 老年 | zh-CN-ZhiyuanNeural | 男 |
| 少女 | zh-CN-XiaoxiaoNeural | 女 |
| 反派 | zh-CN-YunzeNeural | 男 |
| → fallback | zh-CN-XiaoxiaoNeural | 女 |

### 音色持久化方案

1. `CharacterProfile` 添加 `voiceName: String` 字段（存储 Azure 音色名，如 `"zh-CN-XiaoxiaoNeural"`）
2. `Store` 维护静态音色映射表 `defaultVoiceMap: [String: String]`（角色类型 → 音色名），存 `UserDefaults`
3. 用户可在 `CharacterEditorView` 中修改单个角色的 `voiceName`
4. 合成时：`char.voiceName ?? defaultVoiceMap[char.gender/role/tone] ?? fallback`

```swift
extension CharacterProfile {
    // 新增字段
    var voiceName: String  // "zh-CN-XiaoxiaoNeural"，默认为空字符串
}

extension Store {
    static let defaultVoiceMap: [String: String] = [
        "narrator": "zh-CN-YunjianNeural",
        "male_lead": "zh-CN-YunxiNeural",
        "female_lead": "zh-CN-XiaoyiNeural",
        "male": "zh-CN-YunxiNeural",
        "female": "zh-CN-XiaoxiaoNeural",
        "elderly": "zh-CN-ZhiyuanNeural",
        "young_girl": "zh-CN-XiaoxiaoNeural",
        "villain": "zh-CN-YunzeNeural",
    ]
    
    func resolveVoice(for profile: CharacterProfile) -> String {
        if !profile.voiceName.isEmpty { return profile.voiceName }
        if profile.isNarrator { return Self.defaultVoiceMap["narrator"]! }
        let key: String
        switch profile.age {
        case "老年": key = "elderly"
        case "少年", "青年": key = profile.gender == "女" ? "young_girl" : "male"
        default: key = profile.gender == "女" ? "female" : "male"
        }
        return Self.defaultVoiceMap[key] ?? "zh-CN-XiaoxiaoNeural"
    }
}
```

### SSML 情绪兼容确认

Edge TTS API（edge-tts Python 库）对中文 Azure TTS 音色的 `mstts:express-as` 支持情况:

| emotionTag | Azure SSML | edge-tts 支持 | 说明 |
|-----------|-----------|---------------|------|
| angry | `<mstts:express-as style="angry">` | ✅ | 所有 zh-CN 音色 |
| happy | `<mstts:express-as style="cheerful">` | ✅ | 部分音色不支持 → fallback neutral |
| sad | `<mstts:express-as style="sad">` | ✅ | 所有 zh-CN 音色 |
| neutral | 不输出情绪标签 | ✅ | 默认 |
| questioning | `<mstts:express-as style="sad">` | 部分 | 用 `prosody pitch="+2st" contour="(0%,+20Hz) (100%,+20Hz)"` 替代 |

edge-tts relay 服务端收到 `{"ssml": "<speak>...</speak>"}` 后，传递给 edge-tts CLI 的 `--voice` + SSML stdin 参数。如 relay 不支持 `mstts:express-as`，服务端可 strip 情绪标签降级。

**客户端行为建议：**
```swift
// SSML 构建时：
if let emotion = emotionTag, emotion != "neutral" {
    // 添加 mstts:express-as 标签
    // 不验证服务端支持——服务端不支持的会自动忽略
}
// 不阻塞播放，情绪是锦上添花
```

### Docker 部署说明

**仓库**: `https://github.com/fzdymy/tts`

```bash
# 1. 克隆
git clone https://github.com/fzdymy/tts.git
cd tts

# 2. 启动（Docker Compose，推荐）
docker compose up -d
# 默认端口 5050，健康检查: curl http://localhost:5050/health

# 3. 或纯 Docker
docker run -d \
  --name edge-tts \
  -p 5050:5050 \
  -v edge-tts-cache:/app/cache \
  --restart unless-stopped \
  ghcr.io/fzdymy/tts:latest

# 4. 验证
curl -X POST http://localhost:5050/synthesize \
  -H "Content-Type: application/json" \
  -d '{"ssml": "<speak><voice name=\"zh-CN-XiaoxiaoNeural\">你好世界</voice></speak>"}' \
  -o test.wav

# 可选的 Docker Compose 文件 (docker-compose.yml):
# version: "3.8"
# services:
#   edge-tts:
#     image: ghcr.io/fzdymy/tts:latest
#     ports:
#       - "5050:5050"
#     volumes:
#       - edge-tts-cache:/app/cache
#     environment:
#       - TZ=Asia/Shanghai
#       - REQUEST_TIMEOUT=60
#       - CACHE_SIZE=500
#     restart: unless-stopped
# volumes:
#   edge-tts-cache:
```

iOS 端配置: 用户输入 `http://<服务器IP>:5050`，Store 存储到 `UserDefaults`。首次开播前调用 `GET /health` 验证连通性。

### 离线降级路径

Edge TTS 服务器不可达时仍可朗读：

```
playChapterStreaming() 中:
│
├─ [合成前检查]
│    if !(try? await EdgeTTSService.shared.checkHealth()).isAvailable {
│        fallbackToSystemTTS()  // 不阻塞播放
│    }
│
└─ [合成调用]
     do {
         let audioData = try await EdgeTTSService.shared.synthesize(...)
         // → 正常播放
     } catch {
         fallbackToSingleSentenceTTS(sentence)
     }
```

```swift
func fallbackToSystemTTS(paragraphs: [String]) async {
    // AVSpeechSynthesizer 逐段朗读
    for text in paragraphs {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        speechSynthesizer.speak(utterance)
    }
    // 失去多角色区分、失去情绪控制、失去逐句跳过
    // 但用户至少能听
}

private func fallbackToSingleSentenceTTS(_ sentence: String) async {
    // TaskGroup 子任务合成失败时调用
    // 用系统语音朗读单句，然后继续播放下一个
    let utterance = AVSpeechUtterance(string: sentence)
    utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
    speechSynthesizer.speak(utterance)
    // 注意：AVSpeechSynthesizer 异步播放，需要 delegate 等待
}
```

**EdgeTTSService 添加健康检查：**
```swift
func checkHealth() async -> Bool {
    guard let url = URL(string: serverURL)?.appendingPathComponent("health") else {
        return false
    }
    var req = URLRequest(url: url)
    req.httpMethod = "HEAD"
    req.timeoutInterval = 5
    do {
        let (_, resp) = try await URLSession.shared.data(for: req)
        return (resp as? HTTPURLResponse)?.statusCode == 200
    } catch {
        return false
    }
}
```

**Store 启动时检查：**
```swift
// 在 playChapterStreaming 开头
let online = await EdgeTTSService.shared.checkHealth()
if !online {
    await MainActor.run { statusMessage = "Edge TTS 服务器不可达，使用系统语音朗读" }
    fallbackToSystemSpeech()
    return
}
```

### Voice 枚举

Edge TTS 支持的中文音色（供用户选择 + 自动分配）：

```swift
enum EdgeVoice: String, CaseIterable, Codable {
    case xiaoxiao = "zh-CN-XiaoxiaoNeural"  // 少女/默认
    case xiaoyi   = "zh-CN-XiaoyiNeural"    // 女主
    case yunjian  = "zh-CN-YunjianNeural"   // 旁白
    case yunxi    = "zh-CN-YunxiNeural"     // 男主
    case zhiyuan  = "zh-CN-ZhiyuanNeural"   // 老年
    case yunze    = "zh-CN-YunzeNeural"     // 反派
    case yunyang  = "zh-CN-YunyangNeural"   // 沉稳
    case xiaochen = "zh-CN-XiaochenNeural"  // 活泼
    case xiaohan  = "zh-CN-XiaohanNeural"   // 温和
    case xiaomeng = "zh-CN-XiaomengNeural"  // 可爱
    case xiaomo   = "zh-CN-XiaomoNeural"    // 知性
    case xiaoqiu  = "zh-CN-XiaoqiuNeural"   // 自然
    case xiaorui  = "zh-CN-XiaoruiNeural"   // 成熟
    case xiaoshuang = "zh-CN-XiaoshuangNeural" // 年轻
    case xiaoyan  = "zh-CN-XiaoyanNeural"   // 亲切
    case xiaoyou  = "zh-CN-XiaoyouNeural"   // 可爱
    case xiaozhen = "zh-CN-XiaozhenNeural"  // 成熟
    case yunfeng  = "zh-CN-YunfengNeural"   // 稳重
    case yunhao   = "zh-CN-YunhaoNeural"    // 深沉
    case yunjie   = "zh-CN-YunjieNeural"    // 活力
}
```

### 实现: EdgeTTSService.swift

```swift
import Foundation

actor EdgeTTSService {
    enum Config {
        // 默认端口 5050（匹配 edge-tts 仓库默认端口）
        static let defaultHost = "http://localhost:5050"
        static let serverTimeout: TimeInterval = 30
    }

    // 运行时配置
    private var serverURL: String
    private(set) var isAvailable: Bool = false

    static let shared = EdgeTTSService()

    init(serverURL: String = Config.defaultHost) {
        self.serverURL = serverURL
    }

    func updateServerURL(_ url: String) {
        serverURL = url
        // 验证可达性
        Task { await checkAvailability() }
    }

    func checkAvailability() async {
        guard let url = URL(string: serverURL) else {
            isAvailable = false; return
        }
        // HEAD 请求验证端点
        var request = URLRequest(url: url.appendingPathComponent("health"))
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        do {
            let (_, resp) = try await URLSession.shared.data(for: request)
            isAvailable = (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            isAvailable = false
        }
    }

    /// 合成单句（带 SSML 标记）
    func synthesize(
        text: String,
        speaker: String,
        rate: String = "+32%",
        pitch: String = "+0%",
        emotion: String? = nil
    ) async throws -> Data {
        guard let url = URL(string: serverURL) else {
            throw TTSError.downloadFailed("Edge TTS 服务器地址无效")
        }

        // 构建 SSML
        // 中文角色标签告诉 TTS 发音人风格
        let ssml = buildSSML(text: text, speaker: speaker, rate: rate, pitch: pitch, emotion: emotion)
        let body = try JSONEncoder().encode(["ssml": ssml])

        var request = URLRequest(url: url.appendingPathComponent("synthesize"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = Config.serverTimeout

        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw TTSError.downloadFailed("Edge TTS 合成失败 (HTTP \(String(describing: (resp as? HTTPURLResponse)?.statusCode ?? 0)))")
        }
        return data  // WAV 流
    }

    /// 多段对话 SSML 构建
    private func buildSSML(
        segments: [(speaker: String, text: String, emotion: String?)],
        defaultRate: String = "+32%",
        defaultPitch: String = "+0%"
    ) -> String {
        var ssml = """
        <speak xmlns="http://www.w3.org/2001/10/synthesis" xmlns:mstts="http://www.w3.org/2001/mstts" version="1.0" xml:lang="zh-CN">
        """
        for seg in segments {
            let emotionAttr = seg.emotion.map { " mstts:express-as=\"\($0)\"" } ?? ""
            let rate = defaultRate
            let pitch = defaultPitch
            ssml += """
            <voice name="zh-CN-XiaoxiaoNeural"><prosody rate="\(rate)" pitch="\(pitch)"\(emotionAttr)>
            \(seg.text)
            </prosody></voice>
            """
        }
        ssml += "</speak>"
        return ssml
    }

    // 用于兼容 CosyVoice 的多角色嵌入 API
    nonisolated func synthesizeDialogueWithEmbeddings(
        segments: [(speaker: String, text: String, emotion: String?)],
        speakerEmbeddings: [String: [Float]],
        speakerSamples: [String: URL],
        registry: VoiceEmbeddingRegistry?
    ) async throws -> Data {
        // 转换为 SSML 分段（忽略 embedding——Edge TTS 不需要声纹）
        return try await synthesizeSegments(segments.map {
            (speaker: $0.speaker, text: $0.text, emotion: $0.emotion)
        })
    }

    private func synthesizeSegments(_ segments: [(speaker: String, text: String, emotion: String?)]) async throws -> Data {
        // 为避免过长 SSML 被截断，按段落分组合成
        var combinedData = Data()
        for seg in segments {
            let audioData = try await self.synthesize(text: seg.text, speaker: seg.speaker, emotion: seg.emotion)
            combinedData.append(audioData)
        }
        return combinedData
    }
}

// TTSError.timeout 已在其他地方定义，此处不需要重复
```

**2. 修改 `Store.swift` — 集成 EdgeTTSService**

```swift
// 删除 CosyVoiceService.shared 的所有引用
// playChapterStreaming 中:
//   旧: audioData = try await CosyVoiceService.shared.synthesizeDialogueWithEmbeddings(...)
//   新: audioData = try await EdgeTTSService.shared.synthesize(text: sentence, speaker: canonical, emotion: refined.emotionTag)
```

**3. 修改 `TTSView.swift` — 添加 Edge TTS 配置 UI**

```swift
// 添加：
// - 开关 "Edge TTS 备选" (toggle)
// - 服务器 URL 输入框 (TextField)
// - "测试连接" 按钮
// - 连接状态指示 (isAvailable)
```

**4. 缓存策略**

```swift
// Edge TTS 不使用模型缓存（零模型）
// 但合成音频可以共享 CosyVoice 的磁盘缓存
// 缓存键前缀 "edge:" + SSML hash
extension EdgeTTSService {
    func synthesizeWithCache(text: String, speaker: String, ...) async throws -> Data {
        let key = "edge:\(text):\(speaker)"
        if let cached = cache.object(forKey: key as NSString) {
            return cached as Data
        }
        let data = try await synthesize(...)
        cache.setObject(data as NSData, forKey: key as NSString)
        return data
    }
}
```

### 集成测试
1. 确保 `EdgeTTSService` 在无网络 / 服务器离线时不阻塞播放
2. 切换 `useEdgeTTS` 开关后，下一句使用新的 Provider 合成
3. 验证 CosyVoice → Edge TTS 切换不丢失播放队列

---

## 实现要求

1. **CosyVoiceService.swift 整文件删除** — 不保留任何死代码。
2. **CharacterProfile 简化** — 删除 `voiceSampleEmbedding`、`voiceSampleURL`、`voice`、`aliases` 字段（aliases 在说话者推断中仍需要？如果仍使用别名解析则保留）。
3. **VoiceEmbeddingRegistry.swift 删除** — 不再需要声纹注册表。
4. **BertSpeakerDetector.swift 删除** — BERT 是 CosyVoice CAM++ 相关，Edge TTS 不需要。
5. **TTSView.swift 重写** — 删除模型下载/代理/变体/导入 UI，替换为 Edge TTS 服务器 URL 配置 + 连接测试。
6. **EdgeTTSService.swift 新建** — 唯一 TTS 引擎，HTTP SSML 客户端。
7. **Store.swift playChapterStreaming 简化** — 删除 embedding 注册、CosyVoice 调用、progressTask，只保留: parseDialogueSegments → DramaDirector → EdgeTTSService → AudioController。
8. **性格/情绪管线保留** — `CharacterAnalyzer.analyzeSentenceTone` + `DramaDirector.contextualize` 仍用于 SSML `mstts:express-as` 标签。
9. **所有改动基于 commit `8350660`**。先 CI 编译通过。
10. **每处修改附带 git diff 格式** — oldString/newString 精确匹配。