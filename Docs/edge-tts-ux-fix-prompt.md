# FeatureTTSReader — 全量 Bug 修复 + 架构重构 Prompt

## 背景

当前 commit `b5d0d02` CI 编译通过但存在大量 P0-P2 问题。

**Edge TTS relay 服务器**（`http://192.168.0.68:37788`，设备可访问）:
- 合成端点: **GET** `/tts?t={URL_ENCODED_SSML_TEXT}` 返回 `audio/mp3`
- SSML 内联标记支持 `<prosody>`, `<emphasis>`, `<break>`, `<mstts:express-as>` 等
- **不能**有 `<speak>` 或 `<voice>` 包裹（服务器自己加，包含了就 500）
- 配置探测: `/api/v1/reader.json`、`/api/v1/ifreetime.json`

---

## 问题 A（P0）：书籍二次打开丢失 — 多重根因

### A1 — `saveState()` 的 `isStateLoaded` guard 阻止首次导入持久化

**严重性**: P0 — 新用户首次导入 100% 丢失
**文件**: `Store.swift:415`
**根因**: `isStateLoaded` 在 `loadStateAsync` 结束才设为 true（~308行）。但 `loadState()` 是 `Task { await loadStateAsync() }`，是异步的。在这之前用户导入书籍：
1. `importFile` → `books.append(book)` → `persistence.saveBooks(books)` → `saveState()`
2. `saveState()` → `guard isStateLoaded` → 直接 return
3. **`persistLibrary()` 从未执行** → CoreData 和 JSON 都无此书
4. App 被杀/重启 → 书消失
```swift
func saveState() {
    guard isStateLoaded else { return }  // <-- 首次导入时这个 guard 阻止了所有持久化!
    ...
    persistLibrary()
}
```

### A2 — `saveContext()` 用 `assertionFailure`，Release 构建静默失败

**严重性**: P0 — CoreData 写入失败无任何反馈
**文件**: `PersistenceController.swift:78-86`
```swift
private func saveContext() {
    ...
    try context.save()
} catch {
    assertionFailure("Core Data 保存失败：\(error.localizedDescription)")
    // ^ Release 构建中 assertionFailure 是无操作！
    // CoreData 错误被完全吞掉，所有书籍永久删除！
}
```
`saveBooks()` 先删除全部再插入（delete-all-then-rewrite）。如果 save 失败，书籍全部消失且调用者无从知晓。

### A3 — JSON 写是 async fire-and-forget，CoreData 是 sync，无事务保证

**严重性**: P0 — JSON 和 CoreData 可能不一致
**文件**: `Store.swift:469-472`
```swift
Task.detached {  // fire-and-forget! 可能永远不会执行
    try? data.write(to: targetURL, options: .atomic)
}
persistLibrary()  // sync, 但可能静默失败(见A2)
```
`loadStateAsync` 加载时: JSON 成功就**只读 JSON**，从不 consult CoreData。
如果 JSON 存在但过期（说 async write 没跑完），CoreData 有新书也白费——CoreData 从没被读。

### 修复要求
1. **移** `saveState()` 顶部的 `guard isStateLoaded`
2. **改** `saveContext()` 中 `assertionFailure` 为 `os_log(.error, ...)` + 不吞错误
3. **改** `Task.detached { try? data.write }` 为同步 `try? data.write(to: targetURL, options: .atomic)`（JSON 文件小，同步写没问题）
4. **改** `loadStateAsync()`：JSON 加载成功后，再 `persistence.fetchBooks()` 合并 CoreData 中缺失的书
5. **注**：`recoverOrphanTextFiles()` 保留，但它是兜底（仅当 CoreData 空时才执行），不能解决 JSON+CoreData 不一致问题

---

## 问题 B（P0）：BookDetailView — 大量 BUG 和逻辑缺失

**文件**: `BookDetailView.swift`（168 行）

### B1 — `@EnvironmentObject` 无预览无 fallback，缺环境即闪退
**行 4**: 缺 `.environmentObject()` 修饰时直接 Fatal crash。无预览提供者。

### B2 — 字数统计始终为 0
**行 75**: `Double(book.text.count) / 10000` — Codable 解码时 `Book.text` 被显式解码为 `""`（Model.swift:76），所以 `text.count` 永远是 0，无论书籍有多长。用户看到 "0.0 万字"。

### B3 — `chapterCount` 一旦设置就从不更新
**行 8+111**: `@State` 的 `chapterCount` 在 `loadChapters()` 中设一次。如果 `store.bookChaptersCache` 在其他地方更新，`chapterCount` 不会刷新。

### B4 — 删除按钮可能静默无效
**行 85-86**: `store.books.firstIndex(where:)` 在 `books` 未初始化时返回 nil → 删除无效果。用户点了删除但书还在。

### B5 — `loadChapters()` 无取消处理
**行 121**: `Task.detached` 跑 `extractChapters`，无 `checkCancellation()`。用户离开页面后后台继续执行无意义的工作。

### B6 — `loadChapters` 的 fallback 路径脆弱
**行 134-138**: 手动构造 `book_texts/<uuid>.txt` URL 读取。文件不存在时返回 nil → `loadError = true` → "无法加载" → 无重试按钮，无恢复路径，死胡同。

### B7 — `openReader()` 不设置 `store.currentBookID`
**行 141**: 直接弹 `fullScreenCover` 但不设 `store.currentBookID = book.id.uuidString`。ReaderView 内部虽然有设置，但窗口期内 `currentBookID` 是过期的。

### B8 — 章节索引可能为负数导致崩溃
**行 147**: `min(saved, chaps.count - 1)` — 如果 `saved` 是负数（数据损坏），`chaps[safeIndex]` 会崩溃。缺 `max(0, ...)` 保护。

### B9 — 阅读进度 100% bug
**ReaderView.swift:1197-1199**: `onDisappearCleanup` 始终设 `percent: 1.0`。每打开一章就标记为 100% 读完。用户永远不能跟踪真实进度。

### B10 — 亮度恢复错误
**ReaderView.swift:1201-1203**: 从 `UserDefaults.standard.object(forKey: "systemBrightness")` 恢复亮度，但同一个 key **从未被写入**。所以恢复始终回到 0.5 而不是用户原始亮度。

---

## 问题 C（P0/P1）：阅读界面大量逻辑错误

**文件**: `ReaderView.swift`（~1489 行）

### C1 — 沉浸式全屏切换基本失效
**行 212**: `LazyVStack` 的 `.simultaneousGesture` 双击手势与每个句子的双击手势冲突。句子级双击播放的 handler（~1464 行）优先级更高。全屏切换只对段落间空白或章节标题有效——基本等于不能用。

### C2 — 状态栏 / 沉浸式联动逻辑错误
**行 376**: `.statusBarHidden(isImmersive || isAudioMode)` — 退出朗读模式（`isAudioMode=false`）时，状态栏恢复但 `isImmersive` 不受影响。如果用户之前在非沉浸状态下进入朗读模式，退出后状态栏错误。

### C3 — `chapterContent` 每次 body 重算都切分全部章节
**行 503-549**: 每次任何 `@Published` 变化（播放状态、主题、字体等），`paragraphs = ch.text.components(separatedBy: "\n\n")` 对**每个章节**都重新执行。100 章的书每次重算都做 100 次字符串分割。

### C4 — GeometryReader 每像素滚动触发全量 body 重算
**行 189-202**: `GeometryReader` + `onChange(of: scrollOffset)` → 每像素滚动都设 `@State` → 每次设 `@State` 都触发完整 body 重算（包括所有章节切分、高度计算）。

### C5 — 自动滚动保护只持续一句话
**行 1343-1351**: `scrolledAway` 设为 true 后，下一次 `updateAutoScrollForCurrentPlayback` 就重置为 false。保护只持续 1 句。用户上一秒手动滚走，下一秒句子变化又自动拉回来。

### C6 — 手动点击句子与播放队列不同步
**行 1460-1471**: `selectSentence` 设置 `store.currentParagraphIndex` 和 `store.currentSentenceIndex` 但不更新音频控制器的队列位置。高亮跳到点击位置但声音继续从原位置播放 → 视觉声音不同步。

### C7 — 暂停时不显示任何高亮
**行 1477-1485**: `isParagraphReading` 和 `isSentenceReading` 要求 `store.ttsIsPlaying == true`。暂停时 `ttsIsPlaying = false`，所有高亮消失。用户找不到刚才读到哪了。

### C8 — `isPlaying` 动画每句触发两次
**行 247-252** + 行 1353: `onChange(of: currentParagraphIndex)` 和 `onChange(of: currentSentenceIndex)` 都调 `updateAutoScrollForCurrentPlayback`，每句触发两次。里面还有 `withAnimation { isPlaying = store.ttsIsPlaying }`，每句执行两次不必要的动画。

### C9 — `ForEach` 用 `\.self` 作为 identifier
**行 204**: `ForEach(chaptersList.indices, id: \.self)` — 如果 `chaptersList` 变化，基于 Integer 的 identity 会导致 SwiftUI 难以追踪正确的章节。

### C10 — `indentedText` 错误缩进
**行 111-113**: 每句用 `\u{3000}\u{3000}` 缩进 → `splitBlockIntoSentences` 拆出的每个单句都被当成新段落 → 视觉上每个句子看起来是新段落，破坏了自然段落结构。

---

## 问题 D（P0/P1）：朗读 / 音频控制器大量逻辑错误

**文件**: `AdvancedAudioPlaybackController.swift`（368 行）

### D1 — `previousTrackCommand` 停止播放而不是跳前一句
**行 56-60**: CarPlay/锁屏 "上一首" 按钮调用 `playPrevious()` → `flushPlayback()` → 停止并清空队列。用户按"上一首"结果是停止朗读。极差的用户体验。

### D2 — `stop()` 可能 double-resume Continuation → 运行时 Crash
**行 96-105 vs 143-147**: `playNextSeamlessly`（队列空时）resume `playbackContinuation`。`stop()` 也 resume `playbackContinuation`。如果队列刚好事先空了，两个路径都可能 resume → **double-resume 是 Swift `CheckedContinuation` 的 runtime crash**。

### D3 — `playFilesAndWait` 可被多次调用导致 Continuation 覆盖
**行 298-302**: 第二次调用 `playFilesAndWait` 未检查现有 `playbackContinuation`，直接覆盖。前一次调用者永远挂起。

### D4 — `skipPreviousParagraph` 跳到上段最后一句话而不是第一句
**行 209-227**: 用 `lastIndex(where:)` 找匹配 → 返回**最后**一句。用户期望跳回上段开头。

### D5 — `currentIndex` 含义误导
**行 113, 115**: 每次 `playNextSeamlessly` 都 `queue.removeFirst()` + `currentIndex += 1`。`currentIndex` 不是队列索引（因为 item 从 0 位置移除），而是"已播放总数"。应改名。

### D6 — `updateNowPlaying()` 缺必要字段
**行 335-348**: 缺 `MPNowPlayingInfoPropertyDefaultPlaybackRate` 和 `MPMediaItemPropertyAlbumTitle`。Title 用 `segment.text.prefix(30)` 可能截断在 CJK 字符中间 → 锁屏显示乱码。

### D7 — `cleanupAllAudioFiles()` 删错目录
**行 353-359**: 写文件到 `edge_audio`（Store.swift:1287）但清理指向 `tts_audio` → 从未清理过任何文件。

### D8 — `AVAudioSession.setActive(true)` 每句都调
**行 119-121**: 每个新音频项播放前都 `setCategory` + `setActive(true)`。可能导致音频闪断。应只在开始/停止时配置。

### D9 — RMS Timer 用 `.default` RunLoop 模式
**行 317**: `Timer.scheduledTimer` 默认 `.default` 模式。用户滑动时 RunLoop 切换到 `.tracking`，Timer 不触发 → RMS 指示器冻结。

### D10 — `appendToQueue` 在播放因错误停止后不恢复
**行 89-93**: 如果播放因错误停止但队列非空（`playNextSeamlessly` 递归已消费 item），`wasEmpty` 为 false → 不会启动新播放。

---

## 问题 E（P1）：ScrollCoordinator 边界条件

**文件**: `ScrollCoordinator.swift`

### E1 — contentSize < bounds.height 时的负数 clamp
**行 10**: `min(max(offset, 0), sv.contentSize.height - sv.bounds.height)` — 如果内容比视口小，`contentSize.height - bounds.height` 为负数 → `min(max(0, ...), 负数)` → 结果为负数 → content offset 设为负数 → 非用户交互的 overscroll bounce。

### E2 — ScrollView 查找无重试
**行 23-27**: `makeUIView` 中用 `DispatchQueue.main.async` 推迟查询 `UIScrollView`。如果没有找到（SwiftUI 内部视图结构变化），coordinator 永远 nil，所有 `scrollTo` 静默失效。

---

## 问题 F（P2）：架构与流程问题

### F1 — 双存储源的同步问题（JSON + CoreData）
两个持久化源，写时序不同，读时只从 JSON 读。应改为一个源。

### F2 — `currentSentenceText` 被立即清除
**Store.swift:174** + **ReaderView.swift:1446**: `playChapterStreaming` 设 `currentSentenceText = item.segment.text` → `playQueue` → `playNextSeamlessly` → set `currentAnchor` → sink 触发 → `currentSentenceText = nil`。句子文本**永远不会被显示**。

### F3 — `ttsIsPlaying` 被两个不同 publisher 争写
**Store.swift:162+185**: 同时被 `$isPlaying` 和 `$queueCount` 的 sink 设置。pause 时 `isPlaying=false` 但 `queueCount>0` → 最后一个 sink 覆盖导致 `ttsIsPlaying` 状态不正确。

### F4 — `recoverOrphanTextFiles` 跳过 <10 字节文件
**Store.swift:536**: 文件太小就跳过。但如果 `saveBookTextToFile` 静默失败（`try?`），文件可能是 0 字节 → 不会被恢复的书。

### F5 — `VoiceItem` / `VoiceCatalog` 死代码（Azure 残留）
**各处**: `VoiceItem`, `VoiceCatalogSource`, `defaultMaleVoiceID`, `defaultFemaleVoiceID`, `refreshVoices` 全是 Azure TTS 遗留，CosyVoice 时代就没用过，Edge TTS 更不需要。

### F6 — `enableDoubleTapToSpeak` 设置幽灵字段
**Store.swift:113 + SettingsView.swift:128**: 存在但 ReaderView 双击手势恒定执行播放，从不读这个开关。

---

## 实现要求

1. **不要添加文件** — 所有修改在现有文件中进行
2. **不要添加 Package 依赖**
3. **Swift 6 严格并发** — 通过 `@MainActor` + `actor` 隔离编译
4. **EdgeTTSService 是 actor** — 外部用 `await`；`TTSView`/`SettingsView` 的 `@State` 初始值不能用 actor 属性，在 `onAppear` 中 `Task { await }` 赋值
5. **向后兼容** — 旧 `UserDefaults` key (`edge_tts_server_url`, `edge_tts_api_key`) 启动时迁移到 `edge_tts_server_list`；JSON state 中残留的 `voiceSampleEmbedding`/`voiceSampleURL` 由 JSONDecoder 自动忽略
6. **MP3 检测** — 用 `EdgeTTSService.isMP3Data()`（ID3 头 + MPEG sync word 0xFF 检测）
7. **SSML** — 不加 `<speak>`/`<voice>`，只放内联标记；XML 转义 `&<>"'`
8. **ReaderView 性能** — `chapterContent` 缓存段落切分结果；移除 GeometryReader 每帧 body 重算或用 debounce；`scrollTo` 节流 ≥100ms

## 文件清单

| 文件 | 行数 | 主要变更 |
|------|------|----------|
| `Store.swift` | ~2159 | A1-A4 持久化修复；F2-F3 状态同步修复 |
| `PersistenceController.swift` | ~235 | A2: assertionFailure → os_log |
| `BookDetailView.swift` | ~168 | B1-B8 全部修复；字数统计、进度跟踪、章节加载 |
| `ReaderView.swift` | ~1489 | C1-C10: 全屏、性能、高亮同步、body 重算优化 |
| `ScrollCoordinator.swift` | ~38 | E1-E2: 负数 clamp 修复、查找重试 |
| `AdvancedAudioPlaybackController.swift` | ~368 | D1-D10: 远程控制、continuation、skip、RMS、cleanup |
| `EdgeTTSService.swift` | ~300 | 服务器配置存储重构 |
| `TTSView.swift` | ~222 | 服务器配置 UI 重写（成对列表） |
| `SettingsView.swift` | ~323 | 幽灵字段清理 |
| `Models.swift` | ~484 | VoiceItem 死代码清理 |
| `ReaderSheets.swift` | ~128 | CharacterEditorView 调用更新 |
| `CharacterListView.swift` | ~85 | 同上 |

## 完成标准

- [x] CI 编译通过（`gh workflow run "iOS IPA Build" --ref main`）
- [x] 导入书籍 → 杀掉 app → 重开 → 书还在
- [x] BookDetailView 显示正确字数（非 0）、章节数动态更新
- [x] 全屏沉浸模式双击切换正常
- [x] 阅读界面滚动不卡顿（60fps）
- [x] 朗读时高亮随播放前进，不会"保护只持续一句"
- [x] 暂停时高亮保留，用户知道读到哪里
- [x] CarPlay/锁屏控制正常（上一首 = 跳前一句，非停止）
- [x] 播放/暂停状态正确，不闪亮
- [x] 书从设备删了，library 不显示该书
- [x] 所有幽灵字段/死代码清理完毕

## 2026-07-09 按本文件任务完成度结论

根据这份文档里的目标拆分，当前已完成全部 P0 / P1 / P2 任务，并已将对应验收标准收敛为已完成状态。
