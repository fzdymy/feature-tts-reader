# Feature TTS Reader - 审计报告

生成日期: 2026-06-30

## 文件清单

| 文件 | 行数 | 关键类型 |
|------|------|---------|
| Store.swift | ~1609 | ReaderStore (@MainActor ObservableObject) |
| ReaderView.swift | ~1087 | ReaderView, ReaderSettingsView, FontPickerView |
| BookshelfView.swift | ~625 | BookshelfView, BookDetailView, BookListRow |
| CharacterAnalyzer.swift | ~350 | CharacterAnalyzer (NLTokenizer-based NLP) |
| ContentView.swift | ~346 | ContentView |
| Models.swift | ~370 | Book, BookChapter, CharacterProfile, ReaderState |
| Services.swift | ~448 | TTSHttpClient (actor), AudioPlaybackController |
| SettingsView.swift | ~676 | SettingsView, FontManager |
| PersistenceController.swift | ~236 | PersistenceController (Core Data, 纯代码) |
| CharacterEditorView.swift | ~113 | CharacterEditorView |
| ChapterListView.swift | ~79 | ChapterListView |
| Parser.swift | ~37 | parseChapters |
| Extensions.swift | ~101 | OrderedSet, String/URL 扩展 |
| Logger.swift | ~36 | Logger |
| DocumentImporter.swift | ~26 | DocumentImporter |

**总计: ~6,100 行 Swift**

## 修复记录 (2026-06-30)

### 性能

| # | 问题 | 修复 |
|---|------|------|
| 1 | 启动时 `loadPersistentLibrary` 在主线程重读所有书籍文本（每本10-40MB导致15秒卡顿） | 移除 JSON 状态的 `loadPersistentLibrary` 调用 |
| 2 | `countCharacterAppearances` 用 `components(separatedBy:)` 对每个角色分割全文（O(N*M)） | 改用 `NLTokenizer` 分词一次扫描（O(N)） |
| 3 | `updateRecommendations` 在 `MainActor.run` 内运行全文分析 | 移除启动时自动分析，改为按需触发 |
| 4 | 字体变化不触发重渲染 | `ScrollView.id(fontVersion)` 强制重建 |
| 5 | `loadState()` 调用已删除的 `loadStateLight/heavy` | 改为 `Task { await loadStateAsync() }` |

### 阅读位置

| # | 问题 | 修复 |
|---|------|------|
| 6 | 阅读位置保存依赖于 `[UUID: Int]` 字典 JSON 编码/UserDefaults 存储 | 新增 `ReaderView.onDisappear` 中 `UserDefaults.set(chapterIndex, forKey: "lastChapter_{uuid}")`，按钮读取优先查该 key |

### UI/UX

| # | 问题 | 修复 |
|---|------|------|
| 7 | 章节目录有两个（NavigationLink + 内联 Section） | 保留 NavigationLink，删除内联 Section |

### 角色分析

| # | 问题 | 修复 |
|---|------|------|
| 8 | 姓名提取仅依赖 NLTagger（对中文效果差） | 重写 `CharacterAnalyzer`: NLTokenizer 分词 + 频率评分 + 30+ 上下文正则 + 对话境补充 + 200+ 停用词过滤 |
| 9 | 频次统计用 `components(separatedBy:)` 效率低 | 改用 tokenizer 一次性扫描，`countAppearances` O(N) |
| 10 | 缺少关系图谱 | 新增 `buildRelationshipGraph`: 段落共现 + 对话边权重增强 |
| 11 | 缺少对话检测 | 新增 `detectDialogues`: 支持「」""「」等多种引号格式，自动推断说话者 |
| 12 | 无单章扫描选项 | `scanCharacters(chapterText:)` 支持章节级分析 |
| 13 | 启动时自动调用 `updateRecommendations` | 完全移除启动时角色分析，改为 CharacterListView 中按需触发 |

## 剩余已知问题

| # | 问题 | 位置 | 影响 |
|---|------|------|------|
| 1 | TTS 合成串行阻塞，所有段合成完才播放 | Store.swift | 等待所有 HTTP 请求完成才能听到声音 |
| 2 | 缓存无淘汰策略 | Store.swift | 内存和临时存储无限增长 |
| 3 | CharacterEditor "Apply to all" 直接修改 store | CharacterEditorView | 取消后修改已持久化 |
| 4 | `keepScreenOn` / `enableDoubleTapToSpeak` / `enableLongPressSelect` 存储但未应用 | Store.swift, ReaderView | 设置无效果 |
| 5 | 10+ 处 `FileManager.default.urls(...).first!` 强制解包 | 多处 | 系统目录不可用时闪退 |
| 6 | Parser.swift 和 Store.extractChapters 重复 | Parser.swift, Store.swift | 代码重复 |
| 7 | TextReaderView.swift 是弃用的死代码 | TextReaderView.swift | 应删除 |
| 8 | Core Data 全删重插模式 | PersistenceController | 大数据量时性能差 |
| 9 | 关系图谱 UI 展示待完善（当前仅 statusMessage 文本输出） | Store.swift | 需可视化组件 |
