# Feature TTS Reader - 代码审计报告

生成日期: 2026-06-29

## 文件清单

| 文件 | 行数 | 关键类型 |
|------|------|---------|
| FeatureTTSReaderApp.swift | 24 | FeatureTTSReaderApp (App) |
| ContentView.swift | 346 | ContentView |
| Store.swift | 1541 | ReaderStore, SpeechSynthesizerDelegateProxy |
| Models.swift | 370 | Book, BookChapter, CharacterProfile, VoiceItem, ReaderState ... |
| Services.swift | 448 | TTSHttpClient (actor), AudioPlaybackController |
| ReaderView.swift | 1126 | ReaderView, ReaderSettingsView, FontPickerView ... |
| TextReaderView.swift | 260 | TextReaderView (已弃用) |
| CharacterEditorView.swift | 113 | CharacterEditorView |
| SettingsView.swift | 676 | SettingsView, AppTheme, BookshelfLayout, FontManager |
| BookshelfView.swift | 676 | BookshelfView, BookGridCard, BookListRow, BookDetailView |
| ChapterListView.swift | 44 | ChapterListView |
| Parser.swift | 37 | parseChapters (全局函数) |
| DocumentImporter.swift | 26 | DocumentImporter |
| PersistenceController.swift | 236 | PersistenceController (Core Data) |
| Extensions.swift | 101 | HapticManager, String/URL扩展 |
| Logger.swift | 36 | Logger |
| **资源** | - | chinese_voices_35.json, full_chinese_voices.json |

**总计: ~6,056 行 Swift**

---

## 关键问题 (按优先级)

### HIGH - 功能性错误

| # | 问题 | 位置 | 影响 |
|---|------|------|------|
| 1 | TTS合成串行阻塞，所有段合成完才播放 | Store.swift:933-962 | 用户等待所有 HTTP 请求完成才能听到声音 |
| 2 | 缓存无淘汰策略 | Store.swift:41, 51 | 内存和临时存储无限增长 |
| 3 | CharacterEditor "Apply to all" 直接修改 store | CharacterEditorView.swift:55-66 | 取消保存后修改已持久化 |
| 4 | `keepScreenOn` 存储但未应用 | Store.swift:70, ReaderView.swift | 设置无效 |
| 5 | `enableDoubleTapToSpeak`/`enableLongPressSelect` 未检查 | Store.swift:68-69 | 设置无效果 |

### MEDIUM - 稳定性/性能

| # | 问题 | 位置 | 影响 |
|---|------|------|------|
| 6 | 10+ 处 `FileManager.default.urls(...).first!` 强制解包 | 多处 | 系统目录不可用时闪退 |
| 7 | Parser.swift 和 Store.extractChapters 重复 | Parser.swift:3, Store.swift:1057 | 代码重复 |
| 8 | 按进度排序逻辑错误 | BookshelfView.swift:31-35 | 多本书时排序失效 |
| 9 | TextReaderView.swift 是弃用的死代码 | TextReaderView.swift | 应删除 |
| 10 | Core Data 全删重插模式 | PersistenceController.swift | 大数据量时性能差 |
| 11 | `maxCacheSize` 只存储不执行 | SettingsView.swift:67 | 误导性 UI |
| 12 | `detectSpeaker` 正则过于基础 | Store.swift:1320-1338 | 对话-角色匹配不可靠 |
| 13 | `AudioPlaybackController` 缺乏 `@MainActor` | Services.swift:110 | 主线程 API 可能在非主线程运行 |

### LOW - 代码质量

| # | 问题 | 位置 |
|---|------|------|
| 14 | `group.next()!` 强制解包 | Store.swift:1033 |
| 15 | `AVAudioPlayer` 存为 `@State` | CharacterEditorView.swift:8 |
| 16 | `SpacerStack` 未使用 | BookshelfView.swift:344-346 |
| 17 | 缩进不一致 | Store.swift:1307 |
| 18 | `CDChapterProgress.id` 与 `chapterID` 重复 | PersistenceController.swift:188-189 |

---

## 架构点评

- **分层**: SwiftUI UI 层 + MVVM (ReaderStore) 业务层 + Core Data 持久层 ✅
- **模块化**: 各部分基本独立，但有耦合（如 BookDetailView 直接修改 store 全局状态）
- **TTS 管线**: 角色检测 → 脚本分段 → 分段合成 → 顺序播放。逻辑正确但实现低效
- **Core Data**: 无 .xcdatamodeld，纯代码构建模式，schema 变更需改代码
- **Parser**: 支持中文章节正则识别，但缺乏多级目录、卷/回/集等标记
- **性能**: 大文本解析 O(n*m)、TTS 串行合成、无缓存淘汰、无预加载

---

## 建议修复顺序

1. 功能性错误 (HIGH #1-5)
2. 稳定性修复 (MEDIUM #6-8)
3. 清理死代码 (MEDIUM #9)
4. 性能优化 (MEDIUM #10-11)
5. 代码质量 (LOW #14-18)
