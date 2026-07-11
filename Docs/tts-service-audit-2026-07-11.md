# TTS Service 全面审计 (2026-07-11)

## 相关文件

| 文件 | 行数 | 角色 |
|------|------|------|
| `EdgeTTSService.swift` | 380 | 核心 TTS 引擎 — Actor HTTP 客户端 |
| `Store.swift` | 2270 | 合成管线编排 |
| `AdvancedAudioPlaybackController.swift` | ~400 | AVAudioPlayer 播放引擎 |
| `Services.swift` | 419 | **死代码** — 旧 AudioPlaybackController |
| `DramaDirector.swift` | 147 | 上下文情绪平滑 |
| `CharacterAnalyzer.swift` | 1010 | 说话者检测 |
| `CharacterScanner.swift` | 133 | 角色扫描 + 音色分配 |
| `CharacterEditorView.swift` | 108 | 角色编辑器 (含试听) |
| `TTSView.swift` | ~400 | TTS 设置 UI |
| `Models.swift` | 534 | 数据类型 |

---

## P0 — 严重 (数据损坏 / 崩溃 / 死锁)

### P0-S1: `playbackContinuation` 双重恢复 → 崩溃
**`Store.swift:1528-1542`** | **`Store.swift:1226-1240` (stopPlayback)**
- 10s 超时 (`asyncAfter`) 和 `$isPlaying` 订阅者都调用了 `cont.resume()`
- `stopPlayback()` 从未 nil 化 `playbackContinuationCancellable`
- `immediateInterruptAndSeek()` 也未清理
- **后果**: `CheckedContinuation` 双重恢复 → 运行时崩溃

### P0-S2: `isBusy` 在空章节上永久 `true`
**`Store.swift:1347-1355`**
- `isBusy = true` 设置后，空章节提前 return 未恢复 `isBusy = false`
- **后果**: UI 永久显示忙碌状态

### P0-S3: AVSpeechSynthesizer `isSpeaking` 过早 false
**`Store.swift:1562-1583` + `Store.swift:2257-2269`**
- 多话语入队后，第一个话语完成就设 `isSpeaking = false`
- **后果**: UI 认为朗读结束，后台实际上还在播

### P0-S4: `Services.swift` 全文件是死代码 (419 行)
**`Services.swift:1-419`**
- `AudioPlaybackController` 和 `AsyncSemaphore` 零处实例化
- 重构 `TTSQueueItem` / `ScriptSegment` 时必须同步改此文件否则编译失败
- `@unchecked Sendable` 若未来被实例化就是数据竞争炸弹

---

## P1 — 高影响 (功能错误 / 静默数据丢失)

### P1-T1: `playChapterStreaming` 管线 Bug

| # | 位置 | 问题 |
|---|------|------|
| T1a | `Store.swift:1390` | **`pIdx = block.globalStart`** 跨段落对话块的所有句子都标记为同一段落索引 → 高亮/跳转错误 |
| T1b | `Store.swift:1364-1452` | **缺少 `Task.isCancelled`** 检查 → 取消延迟 100ms+ |
| T1c | `Store.swift:1475` | **`AudioPrefetcher.waitFor` 无取消支持** → 取消延迟 15s |
| T1d | `Store.swift:1489-1492` | **`ScriptSegment` metadata 硬编码**: `voice:""`, `rate:0`, `pitch:0`, `style:"neutral"` → NowPlaying/UI 信息错误 |
| T1e | `Store.swift:1467, 1481` | **`emotionTag ?? ""`** 作用于非可选字符串 → 死代码掩盖类型 |

### P1-T2: `AudioPrefetcher` 合成失败静默 15s 暂停
**`Store.swift:2214-2254`**
- `try?` 静默丢弃错误 → `store(audioData:)` 收到 nil 时不恢复 continuation
- `waitFor` 等待完整 15s 超时 → 网络故障每句暂停 15s
- 若 `AudioPrefetcher` 在请求进行中被释放 → continuation 永远不恢复 → **死锁**

### P1-T3: Edge TTS 端点 URL 在尾部斜杠时生成双 `/tts`
**`EdgeTTSService.swift:200-205`**
- URL `http://example.com:37788/tts/` → `lastPathComponent == ""` → 追加 `"tts"` → `/tts/tts`
- **后果**: 所有 TTS 请求发往错误端点 → HTTP 404

### P1-T4: `buildSSML` rate/pitch 边界值错误
**`EdgeTTSService.swift:337-346`**
- `case let r where r > 20: rateValue = "+20%"` — 正确语法是 `+20%`
- `case let r where r < -20: rateValue = "-20%"` — 正确
- `default: rateValue = "\(Int(rate))%"` — 如 `rate = 5` → `"5%"` (应 `"+5%"`)
- **后果**: 正 rate/pitch 在默认分支丢失 `+` 前缀 → 服务器可能忽略

### P1-T5: 称呼语 (Vocative) 检测将受话者当作说话者
**`Store.swift:1863`**
- `quoteText.hasPrefix("\(name)，")` → 如 `"林动，你站住！"` 将说话者分配给`林动`（实际是受话者）
- `quoteText.hasPrefix(name)` 裸前缀匹配更宽泛 → `"林动那家伙又惹祸了"` 也分配给林动
- **后果**: `currentLastSpeaker` 被污染 → 后续所有对话说话者错乱

### P1-T6: `DramaDirector` 三个非功能特性

| # | 位置 | 问题 |
|---|------|------|
| T6a | `DramaDirector.swift:72-76` | `blendEmotionTags` → 硬阈值 0.5, 传入 0.3 → **永远返回当前标签**, 叙述者情绪继承完全不工作 |
| T6b | `DramaDirector.swift:84-87` | `interpolateEmotionTag` → 硬阈值 0.5, 传入 0.6 → **永远返回旧标签**, 同说话者情绪平滑完全不工作 |
| T6c | `Store.swift:1415-1442` | `upcomingWindow` 每句先 append 再 removeFirst → **前瞻窗口始终只有当前句**, 高潮预判从不触发 |

### P1-T7: `CharacterScanner.defaultVoice` 永远返回 `""`
**`CharacterScanner.swift:130-132`**
- `defaultVoice(for:voices:)` → `return ""`
- `Store.defaultVoice` (line 2182) 也是 `return ""`
- **后果**: 自动扫描的角色从无音色分配

### P1-T8: `CharacterEditorView` 试听问题

| # | 位置 | 问题 |
|---|------|------|
| T8a | `CharacterEditorView.swift:97-101` | `isPlaying` 在 `player.play()` 后立即 false → 按钮在播放中重新启用 |
| T8b | `CharacterEditorView.swift:88` | `profile.voice` 可能含 Azure ID → 对 Edge TTS 无意义 |
| T8c | `CharacterEditorView.swift:91-93` | AVAudioSession 错误静默丢弃 |
| T8d | `CharacterEditorView.swift:85` | 未存储的 `Task` → 无法取消 |

### P1-T9: `AdvancedAudioPlaybackController`

| # | 位置 | 问题 |
|---|------|------|
| T9a | `AdvancedAudioPlaybackController.swift:29` | `restorePlaybackState()` 空方法 → 播放状态永不恢复 |
| T9b | `AdvancedAudioPlaybackController.swift:208-209` | `skipBackward()` 错误调用了 `playNextSeamlessly()` (向前) → **后跳实际上是前跳** |
| T9c | `AdvancedAudioPlaybackController.swift:127-131` | `Data(contentsOf: url)` 在 `@MainActor` 上同步 I/O → 大文件阻塞 UI |
| T9d | `AdvancedAudioPlaybackController.swift:95, 85, 92` | `isFirst` 参数传入但永不读取 → 误导性 API |
| T9e | `AdvancedAudioPlaybackController.swift:116,82,...` | `currentIndex` 写入但永不读取 → 死变量 |
| T9f | `AdvancedAudioPlaybackController.swift:96-106` | 队列耗尽时未调 `stopRMS()` → Timer 泄漏 |
| T9g | `AdvancedAudioPlaybackController.swift:319-331` | `playFilesAndWait` 创建硬编码 `"旁白"` 的 ScriptSegment |

### P1-T10: `TTSView.swift`

| # | 位置 | 问题 |
|---|------|------|
| T10a | `TTSView.swift:270-272` | `onAppear` 和 `onChange(of:)` 同时调 `loadVoices()` → 竞态显示错误服务器语音 |
| T10b | `TTSView.swift:391-395` | `store.ttsTestAudioURL` TOCTOU 竞态 |
| T10c | `TTSView.swift:297` | API key 明文显示在预览 URL 中 |
| T10d | `TTSView.swift:293-298` | `testStyle` 未 URL 编码 |
| T10e | `TTSView.swift:355-356` | 连接状态显示过期缓存 |
| T10f | `TTSView.swift:389` | `result.contains("成功")` 脆弱中文匹配 |

### P1-T11: `Models.swift` 遗留 Azure 死代码

| # | 位置 | 问题 |
|---|------|------|
| T11a | `Models.swift:350-386` | `ReaderState` 中 7 个 Azure TTS 字段被持久化但永不使用 |
| T11b | `Models.swift:196-207` | 整个 `VoiceItem` 结构体是死代码 |
| T11c | `Models.swift:332` | `CharacterRecommendation.suggestedVoices: [VoiceItem]` 死代码 |

---

## P2 — 中影响 (边缘情况 / 资源泄漏)

### P2-A: 章节缓存强制解包键
**`Store.swift:75`** — `bookChaptersCache.keys.first!` 可能崩溃

### P2-B: `buildScript()` 静默回退整本书
**`Store.swift:1072-1080`** — selectedChapterID 不匹配时静默使用 bookText

### P2-C: `splitIntoPseudoChapters` 硬编码 5000 字/章
**`Store.swift:1631`**

### P2-D: `SpeechSynthesizerDelegateProxy` deinit 泄漏
**`Store.swift:2257-2269`** — AVSpeechSynthesizer 强持有 delegate

### P2-E: `buildGetRequest` 不安全 URL 编码
**`EdgeTTSService.swift:311-331`** — `#`, `&`, `+` 可能破坏 URL

### P2-F: 空 `emotionTag` 发送空 `s=` 查询参数
**`EdgeTTSService.swift:319`** — 服务器可能拒绝

### P2-G: `observeAudioController` 冗余 `Task { @MainActor }` 包装
**`Store.swift:162-189`** — `.receive(on: .main)` 已保证主队列 → 额外 Task 延迟更新一帧

### P2-H: `playWholeBook` 所有章节失败后回退整本书文本
**`Store.swift:1211-1214`**

### P2-I: `guessGender` 默认男性
**`Store.swift:2195-2203`** — 偏斜女性角色音色分配

### P2-J: `serverURLString` setter 丢弃多服务器配置
**`EdgeTTSService.swift:92-95`**

### P2-K: `estimateAttributes` para guard `"一"` 是 no-op
**`CharacterAnalyzer.swift:433`** — 几乎所有中文段落含"一"

### P2-L: `hasSuffix("章")` 误杀如"章邯"角色名
**`CharacterAnalyzer.swift:982`**

### P2-M: `NLTokenizer` 共享可变实例 → 线程不安全
**`CharacterAnalyzer.swift:716-725`** — `@unchecked Sendable` 下并发访问

### P2-N: `cleanupAllAudioFiles` 静态方法范围过宽
**`AdvancedAudioPlaybackController.swift:393-399`**

### P2-O: `skipToSegment` 只能向前跳
**`AdvancedAudioPlaybackController.swift:161-179`** — 向后跳调用 `stop()` 而非回退

### P2-P: `TTSQueueItem.audioData` 被 Codable 丢弃
**`Models.swift:252-253`** — 解码后 audioData 永远 nil

---

## 各文件摘要

| 文件 | P0 | P1 | P2 | 关键问题 |
|------|:--:|:--:|:--:|----------|
| `Store.swift` | 3 | 7 | 8 | 双重恢复, isBusy 卡住, isSpeaking 过早 false |
| `EdgeTTSService.swift` | 0 | 2 | 3 | 双 /tts URL, SSML rate 前缀丢失, 空 s= 参数 |
| `AdvancedAudioPlaybackController.swift` | 0 | 7 | 5 | 后跳向前, 状态不恢复, 同步 I/O, Timer 泄漏 |
| `Services.swift` | 1 | 0 | 0 | **全文件死代码** |
| `DramaDirector.swift` | 0 | 3 | 0 | 三个组件全部不工作 |
| `CharacterAnalyzer.swift` | 0 | 0 | 3 | 名字后缀误杀, tokenizer 不安全, para guard no-op |
| `CharacterScanner.swift` | 0 | 1 | 2 | defaultVoice 永远返回 "" |
| `CharacterEditorView.swift` | 0 | 4 | 0 | isPlaying 过早 false, Task 泄漏 |
| `TTSView.swift` | 0 | 6 | 0 | 竞态加载, API Key 泄露, TOCTOU |
| `Models.swift` | 0 | 3 | 2 | Azure 死代码持续化 |

**总计: P0=4, P1=33, P2=23**

优先级最高的修复：
1. **P0**: 双重恢复修复 → `stopPlayback`/`immediateInterruptAndSeek` 清理 cancellable
2. **P0**: `isBusy` 空章节卡住
3. **P1**: `AudioPrefetcher` 合成失败 15s 暂停
4. **P1**: Edge TTS URL 尾部斜杠损坏
5. **P1**: 说话者称呼语 (Vocative) 方向错误
6. **P1**: SSML rate 前缀丢失
