# 章节导航 & 滚动性能审计 (2026-07-11)

## 背景

Commit 0899be1 尝试用 `ScrollViewReader.scrollTo` 替代 `.scrollPosition(id:)` 做章节导航，避免两套滚动系统竞争。但用户反映**快速滑动仍然卡顿**。

## 根因分析

### Bug 1: ScrollViewReader.scrollTo + LazyVStack 对远距离章节静默失败

```
LazyVStack 创建 500 章
  ↓
proxy.scrollTo("ch_500", anchor: .top)
  ↓
底层调用 UIScrollView.scrollRectToVisible
  ↓
第 500 章的 UIView 不存在（LazyVStack 未预创建）
  ↓
scrollRectToVisible 静默失败
  ↓
标题更新为"第500章"，但内容仍停留在旧位置
```

`ScrollViewReader.scrollTo` 依赖目标 view 实际存在。LazyVStack 只创建视口附近的 view，远距离章节无对应 view → 滚动失败。

**对比：** `.scrollPosition(id:)` 会强制 LazyVStack 创建目标 view（通过 ScrollView 内部机制），因此至少能触发滚动（虽然差一屏）。

| 方法 | 近距章节 (<20章) | 远距章节 (>20章) |
|------|:-:|:-:|
| `.scrollPosition(id:)` | ✅ 可工作(差一屏) | ✅ 可工作(差一屏) |
| `ScrollViewReader.scrollTo` | ✅ 可工作 | ❌ **静默失败** |

### Bug 2: LazyVStack 快速滑动卡顿

每次新章节进入视口 → `ChapterContentView.onAppear` 执行：

```swift
paragraphs = chapter.text
    .components(separatedBy: "\n")
    .filter { !$0.trimmingCharacters(in: TextNormalizer.nonIndentWhitespace).isEmpty }
```

这是一个 main-thread string split + filter。500 章 × 50 段/章 = 25000 次 view 创建密集触发。

另外 `ReaderOverlayView.totalParasInCurrentChapter` 做同样的 split + filter 用于 slider 绑定 getter，每帧重复计算。

### Bug 3: 屏幕内容不符合预期

**场景：** 用户从第 1 章直接跳到第 500 章
1. `navigateToChapter(499)` 立即设置 `currentChapterIndex = 499` → 标题显示"第500章" ✅
2. `proxy.scrollTo("ch_499")` 被调用 → view 不存在 → 滚动不发生 ❌
3. 用户看到标题"第500章"但内容还在第 1 章 → **预期不符**

## 修复方案

### 章节导航：回到 `.scrollPosition(id:)` + 两阶段设置

`.scrollPosition(id:)` 能强制 LazyVStack 创建目标 view，但首次定位差一屏（LazyVStack 估算高度不精确）。

**两阶段修复：**
1. 非动画设置 `scrollPositionID = "ch_N"` → LazyVStack 创建并定位（估算位置，差一屏）
2. 下一个 run loop：先 `scrollPositionID = nil`（不清除视图），再设置 `scrollPositionID = "ch_N"`（此时 LazyVStack 已有实际布局，定位精确）

两阶段均在非动画 Transaction 中执行，无 Animation 竞争。全部使用 `.scrollPosition(id:)` 单一系统，无 `scrollCoordinator` / `proxy.scrollTo` 参与。

### 滚动性能优化

- 预计算 `BookChapter.paragraphs`，避免 `onAppear` 中 main-thread split + filter
- 缓存 `totalParasInCurrentChapter`，避免 slider binding getter 中重复 split

## 变更文件

| 文件 | 变更 |
|------|------|
| `ReaderView.swift` | 删除 ScrollViewReader / pendingChapterNav，还原 scrollPositionID + 两阶段设置 |
| `Models.swift` | BookChapter 添加 `paragraphs: [String]` 预计算字段 |
| `Store.swift` | `extractChapters` / `splitIntoPseudoChapters` 中预计算 paragraphs |
