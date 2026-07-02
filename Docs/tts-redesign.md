# TTS 系统重构设计

## 一、当前问题总结

### 已修复
1. 播放按钮崩溃 ✅
2. 上一章/下一章跳转位置随机 → **改用 UIScrollView.setContentOffset + computed chapterTop** (7b65c5a)
3. 自定义字体无法导入 → **添加 security-scoped URL 处理 + CTFontManagerUnregister 防重** (7b65c5a)
4. 进度条游标定位异常 → **修正 estimatedChapterHeight 中 CJK 字符宽度公式** (7b65c5a)
5. 系统字体选用 + 中文名称显示 ✅

### 未确认（待测试）
- 上一章/下一章能否正确跳转到章节顶部
- 自定义字体能否正常导入
- 进度条游标左右位置是否正确

---

## 二、TTS 系统架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                       Tab: TTS (原"朗读")                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   书架        │  │   TTS        │  │   设置       │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  TTS 管理页面 (原 ContentView → TTSView)                        │
│                                                                  │
│  ┌─────────────────────────────────┐  ┌──────────────────────┐  │
│  │ 服务器列表 (TTSServerList)      │  │ 音色管理 (VoiceMgr)  │  │
│  │ ├ 局域网-主力机 (● 当前)        │  │ ├ 音色库 (40/76)     │  │
│  │ ├ 公网VPS-1                     │  │ ├ 已标注音色         │  │
│  │ ├ 公网VPS-2                     │  │ └ 微调管理           │  │
│  │ └ + 添加服务器                  │  │                      │  │
│  └─────────────────────────────────┘  └──────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ 朗读控制 (Reader playback section)                       │   │
│  │ [播放当前章] [全书] [停止] 角色: xxx  进度: ████░░      │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 三、数据结构设计

### 3.1 TTSServer — TTS 服务器

```swift
struct TTSServer: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String              // 用户自定义名称，如"局域网-主力机"
    var baseURL: String           // e.g. "http://192.168.1.100:8080"
    var apiKey: String            // 可为空
    var isActive: Bool            // 当前是否正在使用
    var maxTextLength: Int        // 该服务器支持的单次最大字符数
}
```

**存储**: UserDefaults key `ttsServers: [TTSServer]`  
**切换**: 修改 `isActive` (同一时间只有一个 Active)，ReaderStore 从 Active 服务器读取 `baseURL` 和 `apiKey`

### 3.2 VoiceProfile — 音色档案（含微调）

```swift
struct VoiceProfile: Identifiable, Hashable, Codable {
    let id: UUID
    let sourceVoiceID: String     // 原始 VoiceItem.id, e.g. "zh-CN-XiaoxiaoNeural"
    var alias: String             // 别名, e.g. "二号男主", "路人甲", "1-10岁小孩"
    var tags: [String]            // 属性标签, e.g. ["男主", "青年", "沉稳"]
    
    // 微调参数（覆盖 TTS API 默认值）
    var rateOffset: Int           // 语速偏移, -100...100
    var pitchOffset: Int          // 音调偏移, -100...100
    var style: String             // 风格, e.g. "cheerful", "sad"
}
```

### 3.3 TagPreset — 标签预设

```swift
struct TagPreset: Identifiable, Codable {
    let id: UUID
    var name: String              // 标签名, e.g. "男主", "女主", "旁白"
    var category: TagCategory     // 分类
}

enum TagCategory: String, Codable, CaseIterable {
    case role       // 角色定位: 男主, 女主, 配角, 旁白
    case age        // 年龄段: 小孩, 青年, 中年, 老年
    case trait      // 性格: 开朗, 沉稳, 温柔, 凶狠
    case roleType   // 角色类型: 主角, 反派, 龙套
}
```

### 3.4 TTSConfig — 全局 TTS 参数

```swift
struct TTSConfig: Codable {
    var defaultRate: Int = 0
    var defaultPitch: Int = 0
    var defaultStyle: String = "neutral"
    var defaultSensitivity: Int = 50
    var playTimeoutSeconds: Double = 30.0
    var maxRetries: Int = 3
}
```

---

## 四、UI 结构规划

### 4.1 Tab Bar 变更

```
TabView {
    BookshelfView()     // 书架
    TTSView()           // TTS ← 原 ContentView("朗读")
    SettingsView()      // 设置
}
```

- 图标不变（play.circle）
- 文字从"朗读"改为"TTS"

### 4.2 TTSView (新) — 主 TTS 管理页面

```
┌──────────────────────────────────────┐
│  TTS                         [刷新]  │ <- NavBar
├──────────────────────────────────────┤
│  ┌─ 当前服务器 ───────────────────┐  │
│  │  [▼ 局域网-主力机]   ● 已连接  │  │ <- Picker / NavigationLink
│  │  GET /v1/tts   ↑ 5.2ms        │  │ <- 延迟状态
│  └────────────────────────────────┘  │
│                                      │
│  ┌─ 音色管理 ────────────────────┐  │
│  │  [经典40] [全音色76]          │  │ <- VoiceCatalogSource 切换
│  │  ┌────────────────┐           │  │
│  │  │ 晓晓 ◇         │           │  │ <- 已标注（带别名）
│  │  │ 云希 ◇         │           │  │
│  │  │ 晓萱 + 添加别名 │           │  │ <- 未标注
│  │  └────────────────┘           │  │
│  │  微调管理 ▶                   │  │ <- NavigationLink
│  └────────────────────────────────┘  │
│                                      │
│  ┌─ 朗读控制 ────────────────────┐  │
│  │  [播放当前章] [全书] [停止]   │  │
│  │  角色: 旁白(晓晓)             │  │
│  │  进度: ████████░░ 78%        │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

### 4.3 TTSServerListView — 服务器列表

```
┌──────────────────────────────────────┐
│  服务器列表                   [+ 添加]│
├──────────────────────────────────────┤
│  ○ 局域网-主力机                     │ <- Radio button
│    http://192.168.1.100:8080         │
│    最大长度: 1024字符  延迟 5ms      │
│  ○ 公网VPS-1                         │
│    https://tts.example.com           │
│    最大长度: 2048字符  延迟 123ms     │
│  ○ 公网VPS-2                  ✗ 超时  │
│    https://tts2.example.com          │
├──────────────────────────────────────┤
│  [+ 添加服务器]                       │
└──────────────────────────────────────┘

点击单个服务器进入编辑:
┌──────────────────────────────────────┐
│  编辑服务器                          │
├──────────────────────────────────────┤
│  名称: [局域网-主力机              ] │
│  地址: [http://192.168.1.100:8080  ] │
│  API Key: [·····················  ] │
│  最大字符数: [1024                ] │
│  [测试连接]   → 延迟: 5ms ✓        │
│  [保存]                             │
│  [删除服务器]    (red)              │
└──────────────────────────────────────┘
```

### 4.4 VoiceFineTuneView — 微调管理

```
┌──────────────────────────────────────┐
│  微调管理                    [导出]  │
├──────────────────────────────────────┤
│  ┌─ 音色微调 ─────────────────┐     │
│  │  基准音色: 晓晓(女)        │     │ <- VoiceItem picker
│  │  别名: [二号男主         ] │     │
│  │  标签:                      │     │
│  │  [+男主] [+青年] [+沉稳]  │     │ <- TagChip
│  │                            │     │
│  │  语速偏移: ═══●═══  +20   │     │ <- Slider -100...+100
│  │  音调偏移: ═══●═══  -15   │     │ <- Slider -100...+100
│  │  风格: [▼ 低沉   ]         │     │ <- Picker
│  └────────────────────────────┘     │
│                                      │
│  ┌─ 已创建的微调音色 ─────────┐     │
│  │  晓晓 → 二号男主  [编辑][删除]│  │
│  │  晓晓 → 女管家     [编辑][删除]│  │
│  │  云希 → 旁白       [编辑][删除]│  │
│  └────────────────────────────┘     │
└──────────────────────────────────────┘
```

### 4.5 Style 选择器

TTS API 支持风格列表（每个 VoiceItem.styleList），在微调中用 Picker：

```
[中性 neutral]
[高兴 cheerful]
[悲伤 sad]
[愤怒 angry]
[温柔 gentle]
[严肃 serious]
```

如果 VoiceItem.styleList 不为空，只显示其包含的风格；否则显示全部风格。

---

## 五、数据流

### 5.1 服务器切换

```
用户选择"公网VPS-1"
  → TTSServerList.onSelect(id)
  → ReaderStore.setActiveServer(id)
  → store.apiEndpoint = server.baseURL
  → store.apiKey = server.apiKey
  → store.client = TTSHttpClient(baseURL: serverURL, apiKey: key)
  → 后续所有 TTS 请求使用新服务器
```

### 5.2 音色微调 — 朗读应用

```
朗读章节
  → createScriptSegments(chapter.text)
     → detectSpeaker(text) → 角色名 "陈凡"
     → lookup CharacterProfile(byName: "陈凡")
        → voice = profile.voice
        → 从 VoiceProfiles 中查找是否有 alias = "陈凡" 的微调
           → 如果有: 使用微调的 rateOffset/pitchOffset/style
           → 如果没有: 使用 profile 的 rate/pitch/style
     → build ScriptSegment
  → synthesizeAudio(voice:, rate:, pitch:, style:)
```

### 5.3 导出/导入

**导出格式 (JSON)**:
```json
{
  "version": 1,
  "exportedAt": "2026-07-03T12:00:00Z",
  "server": {
    "name": "局域网-主力机",
    "baseURL": "http://192.168.1.100:8080"
  },
  "profiles": [
    {
      "alias": "二号男主",
      "sourceVoiceID": "zh-CN-XiaoxiaoNeural",
      "tags": ["男主", "青年", "沉稳"],
      "rateOffset": 20,
      "pitchOffset": -15,
      "style": "低沉"
    }
  ],
  "tags": ["男主", "女主", "旁白", "小孩", "老人"]
}
```

支持 JSON 和 YAML 格式（用 SwiftYAML 或手写解析）。

---

## 六、TTS API 兼容性要求

当前 API 签名: `GET ?t={text}&v={voice}&r={rate}&p={pitch}&s={style}&api_key={key}`

### 已知限制
1. **最大文本长度**: 需要自动检测（可通过向服务器发 HEAD 或从 `/v1/info` 获取）
2. **并发限制**: 合成大量段落时控制并发数（当前用 `withThrowingTaskGroup` 全并发）
3. **超时处理**: 每段合成最多等 `playTimeoutSeconds`，超时重试 `maxRetries` 次
4. **格式**: 当前返回 MP3，假设所有服务器一致
5. **错误处理**: 服务器返回非 2xx 时，解析 error body 并显示给用户

### 改进方案
- 添加 `/v1/info` 端点探测服务器能力
- 支持 POST 请求（更长文本）
- 文本分段: 如果单段文本超长，自动切分为多个段落分别合成

---

## 七、实现顺序

### Phase 1: 基础重构
1. ContentView → TTSView (重命名 + tab 文字更改)
2. 从 SettingsView 剥离 TTS 服务配置到 TTSView
3. 添加 TTSServer 模型 + 单服务器支持 (兼容现有单 endpoint)
4. 添加 VoiceProfile 模型

### Phase 2: 服务器列表
5. TTSServerList 视图: 添加/编辑/删除/切换服务器
6. 连接测试功能 (ping + 延迟检测)
7. 自动检测 maxTextLength
8. 服务器切换时更新 ReaderStore

### Phase 3: 微调管理
9. VoiceFineTuneView: 基于基准音色创建微调
10. 别名 + 标签系统
11. 微调在朗读中的自动匹配应用
12. 默认经典/全音色基础档案

### Phase 4: 完善
13. 导出/导入 JSON/YAML
14. 风格检测与 Tone Analysis 增强
15. 朗读界面与微调联动 UI

---

## 八、文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| FeatureTTSReaderApp.swift | 修改 | "朗读" → "TTS" |
| ContentView.swift | 重命名 | → TTSView.swift, 结构调整 |
| SettingsView.swift | 修改 | 移除 TTS 服务配置段 |
| Store.swift | 修改 | 添加 TTSServer/VoiceProfile 管理 |
| Models.swift | 修改 | 添加 TTSServer/VoiceProfile/TTSConfig |
| Services.swift | 修改 | 多服务器支持, 连接测试 |
| ReaderView.swift | 修改 | 朗读界面与 VoiceProfile 联动 |
| CharacterEditorView.swift | 修改 | 支持微调别名 |
| VoiceCatalog.swift | 修改 | 添加默认 VoiceProfile 基础数据 |
| **新文件: TTSServerListView.swift** | 创建 | 服务器列表管理 UI |
| **新文件: VoiceFineTuneView.swift** | 创建 | 微调管理 UI |
| **新文件: TTSConfig.swift** | 创建 | 全局 TTS 配置参数 |
