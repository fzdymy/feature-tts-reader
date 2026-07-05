# UX Audit Report — 2026-07-05

## 目标用户流

```
导入小说 → 书架 → 选择章节 → 扫描角色 → 编辑角色(录音) → 一键配音 → 播放(TTS)
                                              ↓
                                        调整音色/语速/情绪
```

---

## 关键问题（按严重程度）

### P0 — 阻止核心流程

#### 1. ReaderView 全章节一次性加载
- **文件**: `ReaderView.swift:168-173`
- **问题**: `LazyVStack` + `ForEach(chaptersList.indices)` 渲染所有章节。300 章的小说 → 内存 OOM
- **修复**: 按需加载当前章节 ± N 章，或改用 `UITextView` / `PDF` 渲染

#### 2. `showCharacterPanel` Sheet 冲突
- **文件**: `ReaderView.swift:414-416` 与 `ReaderView.swift:735-738`
- **问题**: 两个 `.sheet(isPresented: $showCharacterPanel)` — SwiftUI 只认第一个，第二个被静默忽略
- **修复**: 合并到一个 sheet 修饰符

#### 3. SettingsView 设置不自动保存
- **文件**: `SettingsView.swift:102-104`
- **问题**: 修改字体/主题/交互偏好后必须点击"保存所有设置"→ 退出即丢失
- **修复**: 每个修改直接写入 `UserDefaults` 或 store，移除保存按钮

#### 4. CharacterAssignmentView 扫描在主线程
- **文件**: `CharacterAssignmentView.swift:247-431`
- **问题**: `Task { @MainActor in }` 包裹全书扫描（正则+AC自动机+属性分析）
- **修复**: 将计算移出 MainActor，仅在更新 UI 时切回

#### 5. BookshelfView 状态消息被隐藏
- **文件**: `BookshelfView.swift:43`
- **问题**: `showStatus = !store.statusMessage.contains("合成")` — 含"合成"的消息永远不显示
- **修复**: 用独立的状态队列替代字符串包含过滤

### P1 — 严重影响体验

| # | 问题 | 文件 | 详情 |
|---|------|------|------|
| 6 | 全屏点击手势与滚动/文本选择冲突 | ReaderView.swift:176 | `simultaneousGesture(TapGesture())` 覆盖 ScrollView |
| 7 | 角色扫描无取消按钮 | CharacterAssignmentView.swift | `isScanning` 检查 `Task.isCancelled` 但 UI 无取消路径 |
| 8 | TTS 下载无百分比/速度 | TTSView.swift:62 | 1.5GB 下载只有转圈，用户不知道还要等多久 |
| 9 | 声纹提取无加载状态 | CharacterEditorView.swift:234-251 | 点"导入"后 UI 无变化，用户可能反复点 |
| 10 | 两套角色扫描逻辑可能结果不同 | CharacterListView vs CharacterAssignmentView | `scanCharacters()` 和 `startScan()` 流程不同 |
| 11 | CosyVoice 状态轮询延迟 | TTSView.swift:13 | 每 1 秒轮询 actor，低效 |
| 12 | ReaderView `segmentStartOffset` 同步误触发 | ReaderView.swift:159-164 | 用户轻微滚动可能被误判为"手动滚走" |

### P2 — 可优化

| # | 问题 | 文件 |
|---|------|------|
| 13 | `ReaderView.swift` 1996 行，应拆分 | ReaderView.swift |
| 14 | `SettingsView.swift` 706 行含内嵌 FontManagerView | SettingsView.swift |
| 15 | `BookshelfView.swift` 618 行含 BookGridCard/BookDetailView | BookshelfView.swift |
| 16 | `Store.swift` 是上帝对象，所有视图依赖它 | Store.swift |
| 17 | 重复代码：loadChapterCount 在两个视图中相同 | BookshelfView.swift:326-352 vs 410-436 |
| 18 | 重复代码：CJK 字体过滤逻辑在 FontManagerView 和 FontPickerView | SettingsView.swift / ReaderView.swift |
| 19 | `isStopWord` 为实例方法但被静态调用（已修正） | (已修复) |
| 20 | 无统一日志系统（print vs debugLog） | 全局 |
| 21 | TextReaderView 已弃用且构建假 book 对象使进度丢失 | TextReaderView.swift |
| 22 | SettingsView 使用废弃 `UIApplication.shared.windows` API | SettingsView.swift |
| 23 | `clearCache` 删除 cachesDirectory 全部内容 | SettingsView.swift |
| 24 | 备份导出 `ReaderState` 可能遗漏新加的字段 | SettingsView.swift |
| 25 | `CharacterAnalyzer.isStopWord` 是实例方法但被静态引用 | (已修复) |

### P3 — 低优先级

| # | 问题 | 文件 |
|---|------|------|
| 26 | 角色扫描进度文字太技术性（"AC 自动机"等） | CharacterAssignmentView.swift |
| 27 | Grid 卡片与 List 行布局代码重复 | BookshelfView.swift |
| 28 | ChapterListView 无搜索/过滤 | ChapterListView.swift |
| 29 | 录制仅支持 WAV 格式 | CharacterEditorView.swift |
| 30 | 未验证导入音频长度（10-30s 最佳） | CharacterEditorView.swift |

---

## 性能瓶颈

| 操作 | 耗时 | 原因 |
|------|------|------|
| 首次导入 → 书架展示 | 1-5s | `Book.init` 解析全文分章节，主线程 |
| 扫描全书角色 | 5-30s | 正则 × 7 + AC 自动机 × 全文，主线程 |
| 生成朗读脚本 | 3-10s | `parseDialogueSegments` 逐段解析 |
| CosyVoice 首次合成 | 5-60s | 模型未预热时需下载 1.5GB |
| CosyVoice 后续合成 | 1-3s | 模型已预热，但还需 CAM++ 声纹 |
| 声纹提取 | 2-5s | CAM++ Core ML 推理 |
| 切换音色目录 | 1-3s | 重建 VoiceItem[] |

---

## 推荐修改计划

### 立即修复（P0）
1. 合并 `showCharacterPanel` 两个 sheet → 一个
2. SettingsView 移除保存按钮，自动写 UserDefaults
3. BookshelfView 状态消息改用独立队列

### 本周（P1）
4. CharacterAssignmentView 扫描移到后台线程
5. TTSView 添加下载进度百分比（`URLSession` delegate）
6. ReaderView 全章节加载改为按需加载
7. 添加扫描取消按钮

### 本月（P2）
8. 拆分 ReaderView 为多个文件
9. 拆分 SettingsView 抽出 FontManagerView
10. Store 拆分出 BookStore、CharacterStore、SettingsStore
11. 统一日志系统
12. 用 iOS 18 `@Observable` 替换 `ObservableObject`

---

## 公共音频样本来源

| 来源 | URL | 用途 |
|------|-----|------|
| CosyVoice 3 zero_shot_prompt.wav | `FunAudioLLM/Fun-CosyVoice3-0.5B-2512/asset/` | 中文女声默认样本 |
| Qwen3-TTS clone.wav | `qianwen-res.oss-cn-beijing.aliyuncs.com/Qwen3-TTS-Repo/clone.wav` | 英文女声样本 |
| IndexTTS2 (TBD) | — | 待确认 |

下载脚本: `Scripts/download_default_samples.sh`
