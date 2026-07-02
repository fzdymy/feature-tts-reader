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

## 待处理
- 默认经典/全音色基础档案 (3.3)
- 编译错误检查与修复
- CI 验证

