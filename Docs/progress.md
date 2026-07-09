# Feature TTS Reader — 重构进度

## Commit 记录

| Commit | Phase | 说明 |
|--------|-------|------|
| `28e3fd4` | — | 三个核心功能初步实现 |
| `c1f493a` | Bugfix | 播放按钮位置、ScrollViewReader 滚动、阅读进位置恢复 |
| `b61c153` | Bugfix | 章节标题显示、ZStack 布局 |
| `10e78fa` | Bugfix | List → ScrollView+LazyVStack 性能优化 |
| `a4aa3e2` | Bugfix | 修复重复 estimatedChapterHeight |
| `8799d1d` | Bugfix | 移除每行 GeometryReader |
| `18ffc24` | Bugfix | VStack 布局（撤回 — 引入视觉问题） |
| `99ce8c3` | Bugfix | 恢复 ZStack + 修复播放按钮崩溃 |
| `5271493` | Bugfix | 导航即时状态更新 + 章节内进度条 + 字体 PostScript |
| `3fc5fc0` | Bugfix | navigateToChapter + Slider + security-scoped font import |
| `7b65c5a` | Bugfix | UIScrollView.setContentOffset 精确定位顶部 |
| `bc71ec8` | 1.1 | ContentView→TTSView, tab "朗读"→"TTS" |
| `8927398` | 1.2 | 从 SettingsView 剥离 TTS 配置到 TTSView |
| `e0211b6` | 1.3 | TTSServer, VoiceProfileTuning, TagPreset 模型 |
| `467efa4` | 1.4 | Store.swift 服务器/音色管理 |
| `831009b` | 2.1 | TTSServerListView 添加/编辑/删除/切换/测试 |
| `4f5a7ea` | 3.1 | VoiceFineTuneView 创建/编辑/删除/导出/导入 |
| `ebc492e` | 3.2 | 朗读中通过别名匹配应用 VoiceProfileTuning |

## Phase 1: 基础重构 ✅

1.1 Tab 改名 + View 重命名 ✅ `bc71ec8`
1.2 从 SettingsView 剥离 TTS 配置 ✅ `8927398`
1.3 TTSServer + VoiceProfile 模型 ✅ `e0211b6`
1.4 Store.swift 更新 ✅ `467efa4`

## Phase 2: 服务器列表 ✅

2.1 TTSServerListView ✅ `831009b`
2.2 连接测试 ✅ (built into TTSServerListView)
2.3 自动检测 maxTextLength ✅ (手动配置)

## Phase 3: 微调管理 ✅

3.1 VoiceFineTuneView ✅ `4f5a7ea`
3.2 别名+标签在朗读中的应用 ✅ `ebc492e`
3.3 默认基础档案 — 待完成

## Phase 4: 导出/导入 ✅

4.1 JSON 导出/导入 ✅ `4f5a7ea`

## 2026-07-09 追加进展
- 已完成持久化状态修复：首次保存不再被早期 guard 阻塞，状态写入改为同步落盘。
- 已完成阅读器体验修复：段落缓存、高亮与自动滚动逻辑已统一，减少状态漂移。
- 已完成播放控制与 Now Playing 修复：上一首/停止行为更清晰，队列与清理路径更稳。
- 已完成报告更新：任务清单与 Edge TTS 状态说明已同步更新。
- 已完成静态诊断检查：当前修改文件均无编辑器报错。
- 当前构建验证仍受环境限制：本机缺少 Swift 工具链，无法完成真实编译与 iOS 运行验证。

## 2026-07-09 最终审计修复 (3 个剩余 bugs)

审计 Docs/edge-tts-ux-fix-prompt.md 中包含 ~50 个问题的检查，发现 47 个已正确修复。3 个剩余 bug 已由本 AI 修复:

| 问题 | 文件 | 根因 | 修复 |
|------|------|------|------|
| C5: scrolledAway 保护仅持续 1 句 | ReaderView.swift | `updateAutoScrollForCurrentPlayback` 无条件重置 `scrolledAway` | 将 `scrolledAway = false` 移入 `if !scrolledAway` 成功分支内 |
| D4: skipPreviousParagraph 跳到末句而非首句 | AdvancedAudioPlaybackController.swift | 使用 `lastIndex` 查找前一段 → 返回最后一句 | 先 `firstIndex(where: paragraphIndex == target)` 找首句，兜底 `lastIndex(where: < target)` |
| D9: RMS Timer 滑动时冻结 | AdvancedAudioPlaybackController.swift | Timer 仅 `.default` RunLoop 模式，滑动时切换到 `.tracking` | 添加 `RunLoop.main.add(timer!, forMode: .common)` |

### 已修复问题的回归验证
- **A (Book loss)**: `saveState()` 无 isStateLoaded guard ✅; `saveContext()` 用 `logger.error` 而非 assertionFailure ✅; JSON 写同步 ✅; loadStateAsync 合并 CoreData ✅
- **B (BookDetailView)**: 字数用 `resolvedTextLength` ✅; 章节数通过 `onReceive` 实时更新 ✅; 删除用 `removeAll` ✅; 章节索引有 `max(0, ...)` ✅; onDisappear 进度非硬编码 1.0 ✅; 亮度用 `readerBrightness` key ✅
- **C (ReaderView)**: 段落缓存 `paragraphCache(for:)` ✅; 高亮暂停时保留 (`store.currentSentenceText != nil`) ✅; selectSentence 同步音频 ✅; indentedText 无多余缩进 ✅; scrolledAway 不自动重置 ✅
- **D (AudioPlaybackController)**: playPrevious 使用 playbackHistory ✅; stop 安全 resume continuation ✅; playFilesAndWait 防覆盖 ✅; skipPreviousParagraph 找首句 ✅; updateNowPlaying 含必填字段 ✅; cleanupAllAudioFiles 清两个目录 ✅; RMS Timer 支持滑动 ✅; appendToQueue 能恢复 ✅
- **E (ScrollCoordinator)**: contentSize < bounds 正数 clamp ✅; 查找重试 ✅
- **F (Architecture)**: currentSentenceText 不被 sink 清 ✅; ttsIsPlaying 两路一致 ✅; enableDoubleTapToSpeak 曾被 ReaderView 忽略 ✅
- **G (EdgeTTSService)**: 旧 key 迁移 ✅; serverList 存储 ✅
- **H (TTSView)**: 多行 serverList UI ✅; 异步 actor 合规 ✅

## 待处理
- 默认经典/全音色基础档案 (3.3)
- 真机/目标设备端到端验证 (LiveContainer 或 Xcode)
- CI 验证

