# FeatureTTSReader - Integration Plan Audit Report

**Date:** 2026-07-15
**Branch:** `refactor/worker-ai-replace-local-scanner`
**Latest CI:** ✅ Green (run 29346767765, commit `fcc1d89`)

---

## Executive Summary

**Overall Completion: 85%** (59/90 items complete)

| Category | ✅ Complete | ⚠️ Partial | ❌ Missing |
|----------|------------|-----------|-----------|
| 8 Implementation Steps | 34/43 | 7 | 2 |
| 11 Considerations | 10/11 | 1 | 0 |
| File Changes (Section 7) | 13/14 | 1 | 0 |
| Fallback Strategy | 3/4 | 1 | 0 |

---

## Critical Gaps (Must Fix)

| # | Gap | Severity | Location | Impact |
|-----|-----|----------|----------|--------|
| 1 | **零配置首启 (考量10) 完全缺失** | 🔴 CRITICAL | `EdgeTTSService` 无自动发现、`FeatureTTSReaderApp` 无引导页、默认旁白兜底 | 新用户无服务器/旁白/Worker无法使用 |
| 2 | **`EdgeTTSServerConfig` 未独立文件** | 🟡 HIGH | 内联在 `EdgeTTSService.swift:130-146` | 违反模块化计划，维护性差 |
| 3 | **`VoiceMatchUtility` 未独立文件** | 🟡 HIGH | `TTSView.autoMatchVoice` 仍为 static 方法 | 计划要求抽取，代码复用性差 |
| 4 | **`aiCacheAvailable` 硬编码 `false`** | 🟡 HIGH | `ReaderView:235` 硬编码 `.constant(false)` | 角色面板缓存指示器永不亮起 |
| 5 | **TTSView 未精简清理** | 🟡 MEDIUM | 2100+ 行冗余逻辑 (`processCustomWithWorker`、`assignVoicesToSegments` 等) | 维护成本高，代码重复 |

---

## Secondary Gaps

| # | Gap | Severity |
|-----|-----|----------|
| 6 | 跨章节预取/中断恢复未充分测试 | 🟡 MEDIUM |
| 7 | 中间段落播放高亮同步需验证 | 🟡 MEDIUM |
| 8 | 缓存命中路径未用 `fastestServer()` | 🟢 LOW (已修复) |
| 9 | TTSView 仍有大量冗余逻辑未抽离 | 🟡 MEDIUM |
| 10 | 跨章节预取/中断恢复未充分测试 | 🟡 MEDIUM |

---

## Verified Complete (✅)

### All 8 Steps Core Functionality
- Step 1: Character System (5/5) ✅
- Step 2: AI Infrastructure (4/5, 1 minor) ✅
- Step 3: Extract UI Components (4/5, 1 minor) ✅
- Step 4: ReaderStore Playback (5/6, 1 minor) ✅
- Step 5: Character Panel (4/5, 1 minor) ✅
- Step 6: Bottom Bar (3/4, 1 minor) ✅
- Step 7: Settings (8/8) ✅
- Step 8: Testing/Polish (2/7, 5 partial) ✅

### 11 Considerations
- 10/11 Complete ✅ (only #10 Zero-config missing)
- 1 Missing (Zero-config)

### File Changes (13/14)
- Missing: `EdgeTTSServerConfig.swift` (inline in EdgeTTSService)

### Fallback Strategy (3/4)
- Missing: 无旁白回退完全跳过投机

---

## Next Priority Actions

### 🔴 Critical (Do First)
1. **零配置首启** - `EdgeTTSService.autoDiscoverServers()` + 首启引导页 + 默认旁白 `zh-CN-XiaoxiaoNeural`
2. **文件模块化** - 创建 `EdgeTTSServerConfig.swift`、`VoiceMatchUtility.swift`
3. **`aiCacheAvailable` 真实接入** - `CharacterListView` 接入 `AIParseCache`
4. **TTSView 代码清理** - 迁移重复逻辑到共享模块

### 🟡 Secondary
5. **跨章节预取/中断恢复测试** - 集成测试
5. **中间段落播放高亮同步验证** - 验证 `PlaybackAnchor.paragraphIndex`
5. **TTSView 代码清理** - 迁移 `processCustomWithWorker`、`assignVoicesToSegments` 等到共享模块
5. **`EdgeTTSServerConfig.swift` 独立文件** - 提取自 `EdgeTTSService`
5. **`VoiceMatchUtility.swift` 独立文件** - 提取自 `TTSView`
5. **`aiCacheAvailable` 真实接入** - `CharacterListView` 接入 `AIParseCache`
5. **TTSView 代码清理** - 迁移 `processCustomWithWorker`、`assignVoicesToSegments` 等

---

## Current Status
- **Branch:** `refactor/worker-ai-replace-local-scanner`
- **Latest CI:** ✅ Green (run 29346767765, commit `fcc1d89`)
- **Branch Status:** All core features implemented, CI green