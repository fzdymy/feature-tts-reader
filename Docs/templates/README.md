# 模板系统 API 文档

## 一、模板文件格式 (Template JSON Format)

模板文件采用 JSON 格式，顶层为 `TemplateExport` 包装结构，包含版本号、导出时间和模板列表。

### TemplateExport（顶层）

```swift
struct TemplateExport: Codable {
    let version: Int           // 版本号，当前为 1
    let exportedAt: Date       // 导出时间，ISO 8601
    var templates: [RoleTemplate]
}
```

### RoleTemplate（模板）

```swift
struct RoleTemplate: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String                               // 模板名称（如"仙侠玄幻"）
    var roles: [TemplateRole]                      // 角色阵容
    var fallbackMaleVoiceID: String                // 未匹配男性角色的容灾音色 ID
    var fallbackFemaleVoiceID: String              // 未匹配女性角色的容灾音色 ID
    var fallbackRateOffset: Int                    // 容灾语速偏移（-100 ~ 100）
    var fallbackPitchOffset: Int                   // 容灾音调偏移（-100 ~ 100）
    var fallbackStyle: String                      // 容灾风格（如 "neutral"）
}
```

### TemplateRole（角色）

```swift
struct TemplateRole: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String          // 角色名（如"男主（热血少年）"）
    var sourceVoiceID: String  // 推荐音色 ID（如 "zh-CN-YunxiNeural"）
    var voiceSuggestion: String// 音色备注描述（如"阳光少年，修行路上成长型"）
    var rateOffset: Int        // 语速偏移（-100 ~ 100）
    var pitchOffset: Int       // 音调偏移（-100 ~ 100）
    var style: String          // 风格（如 "cheerful", "serious"）
}
```

### 完整 JSON 示例

```json
{
  "version": 1,
  "exportedAt": "2026-07-03T00:00:00Z",
  "templates": [
    {
      "id": "a1b2c3d4-0001-4000-8000-000000000001",
      "name": "仙侠玄幻",
      "fallbackMaleVoiceID": "zh-CN-YunyeNeural",
      "fallbackFemaleVoiceID": "zh-CN-XiaoxiaoNeural",
      "fallbackRateOffset": 0,
      "fallbackPitchOffset": 0,
      "fallbackStyle": "neutral",
      "roles": [
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000011",
          "title": "旁白",
          "sourceVoiceID": "zh-CN-YunyangNeural",
          "voiceSuggestion": "沉稳叙事，专业感，语速稍慢",
          "rateOffset": -10,
          "pitchOffset": -3,
          "style": "professional"
        },
        {
          "id": "a1b2c3d4-0001-4000-8000-000000000012",
          "title": "男主（热血少年）",
          "sourceVoiceID": "zh-CN-YunxiNeural",
          "voiceSuggestion": "阳光少年，修行路上成长型，富有朝气",
          "rateOffset": 5,
          "pitchOffset": 5,
          "style": "narration-relaxed"
        }
      ]
    }
  ]
}
```

---

## 二、模板文件存放位置

- **内置模板文件**位于项目根目录 `templates/` 目录下，为 JSON 格式文件。
- 应用首次启动时（`ReaderStore.init`），通过 `loadRoleTemplates()` 从 `UserDefaults` 加载已导入的模板数据。
- 内置模板 JSON 文件作为初始模板来源，用户可通过导入功能加载至应用。
- 当前内置模板列表见本文档"七、内置模板列表"。

---

## 三、模板应用流程 (applyTemplate)

`applyTemplate(_ template: RoleTemplate)` 是应用模板的核心函数，定义于 `Store.swift:187`。完整流程如下：

```
applyTemplate(template)
  ├─ 1. defaultMaleVoiceID = template.fallbackMaleVoiceID
  ├─ 2. defaultFemaleVoiceID = template.fallbackFemaleVoiceID
  ├─ 3. defaultFallbackRateOffset = template.fallbackRateOffset
  ├─ 4. defaultFallbackPitchOffset = template.fallbackPitchOffset
  ├─ 5. defaultFallbackStyle = template.fallbackStyle
  ├─ 6. 遍历 template.roles:
  │     ├─ 跳过 title 为空的角色
  │     └─ 若 characters 中不存在同名角色（去重）：
  │          创建 CharacterProfile(name=role.title, voice=role.sourceVoiceID,
  │          rate=role.rateOffset, pitch=role.pitchOffset, style=role.style)
  │          追加至 characters 数组
  └─ 7. 设置 statusMessage = "已应用模板「{name}」，{n} 个角色已导入"
```

**后续朗读流程**：`buildScript` → `createScriptSegments` 中，角色匹配使用 `characters` 数组中的 `CharacterProfile`。若文本中存在角色未被匹配到任何已有 profile，则进入容灾机制。

---

## 四、容灾机制 (Fallback Mechanism)

当 `createScriptSegments` 遇到未在任何 `CharacterProfile` 中登记的角色时（`profile.voice.isEmpty && speakerProfile == nil`），按以下优先级选出音色：

```
1. guessGender(speaker) 启发式判断性别
   └─ 男性 → 使用 defaultMaleVoiceID（来自模板容灾设置）
   └─ 女性 → 使用 defaultFemaleVoiceID
   └─ 同时应用 defaultFallbackRateOffset / PitchOffset / Style

2. 若容灾音色 ID 为空 → defaultVoice() 兜底
   └─ 根据性别、语气等匹配最佳音色
   └─ 最终保底: "zh-CN-XiaoxiaoNeural"
```

### guessGender() 判断逻辑

定义于 `Store.swift:2027`，基于中文名字特征字启发式判断：

```swift
男性特征字: 哥, 爷, 叔, 伯, 爸, 弟, 雄, 强, 刚, 龙, 虎, 伟, 勇, 军, 杰, 涛, 明, 飞, 浩, 剑, 峰, 渊, 恒, 毅, 宏
女性特征字: 妹, 姐, 妈, 姑, 姨, 娘, 女, 花, 丽, 美, 娜, 婷, 芳, 娟, 玲, 静, 淑, 玉, 娇, 凤, 燕, 秀, 莲, 英
```

遍历名字中的每个字，优先命中男性字则返回 `true`，命中女性字返回 `false`。若均未命中，默认返回 `true`（男性），因为网文角色比例男性偏高。

---

## 五、导入/导出 (Import/Export)

### 导出

模板管理界面提供"导出模板 (JSON)"按钮，调用 `exportRoleTemplates()`：

- 将 `roleTemplates` 数组包装为 `TemplateExport(version: 1, exportedAt: Date(), templates: roleTemplates)`
- 通过 `JSONEncoder` 编码为 Data
- 使用 SwiftUI `fileExporter` 写入用户选择路径

### 导入

通过 `fileImporter` 读取用户选择的 JSON 文件，调用 `importRoleTemplates(from data: Data)`，验证流程如下：

| 验证步骤 | 失败时提示 |
|----------|-----------|
| 文件是否为空 | "导入失败: 文件为空" |
| JSON 格式是否正确 | "导入失败: JSON 格式错误或字段不匹配" |
| 模板列表是否为空 | "导入失败: 模板列表为空" |
| 模板名是否为空（trim） | 跳过（skippedCount++） |
| 角色列表是否为空 | 跳过（skippedCount++） |
| 过滤后有效角色是否为空 | 跳过（skippedCount++） |
| 是否与已有模板 ID 重复 | 跳过（skippedCount++） |
| 全部通过 → 追加至 roleTemplates | 导入成功计数++ |

导入结果通过 `statusMessage` 显示，格式如 `"导入成功: 3 个模板已添加，1 个已跳过"`。

---

## 六、模板编辑界面说明

`TemplateEditView` 提供模板编辑界面，主要分为三个区域：

### 6.1 模板名称

- 输入框：`TextField`，字符串必填，保存按钮在名称为空时禁用

### 6.2 未匹配角色容灾

当朗读时遇到未在角色阵容中登记的角色名，使用以下参数：

| 字段 | 控件 | 说明 |
|------|------|------|
| 男性默认音色 | Picker | 从 `voices` 列表选择，可选"不指定" |
| 女性默认音色 | Picker | 同上 |
| 容灾语速 | Stepper | -100 ~ 100，步长 5 |
| 容灾音调 | Stepper | -100 ~ 100，步长 5 |
| 容灾风格 | Picker | neutral / cheerful / sad / angry / gentle / serious |

### 6.3 角色阵容

每个角色行包含：

| 字段 | 控件 | 说明 |
|------|------|------|
| 角色名 | TextField | 如"男主（热血少年）" |
| 音色 | Picker | 从 `voices` 列表选择 |
| 音色备注 | TextField | 如"阳光少年，修行路上成长型" |
| 语速 | Stepper | -100 ~ 100，步长 5 |
| 音调 | Stepper | -100 ~ 100，步长 5 |
| 风格 | Picker | 同上 |

支持添加角色（`"+ 添加角色"` 按钮）和删除角色（滑动删除）。

---

## 七、内置模板列表

项目 `templates/` 目录下包含五个内置模板：

| 文件名 | 模板名称 | 角色数 | 适用类型 |
|--------|----------|--------|----------|
| `xianxia-fantasy.json` | 仙侠玄幻 | 7 | 男频修仙、玄幻小说 |
| `urban-ceo.json` | 都市商战·霸总 | 7 | 都市言情、霸道总裁 |
| `historical-time-travel.json` | 历史穿越 | 7 | 穿越、架空历史 |
| `modern-romance.json` | 现代言情·甜宠 | 6 | 现代恋爱、甜宠文 |
| `sci-fi.json` | 科幻未来 | 7 | 科幻、赛博朋克、星际 |

各模板的角色配置及推荐音色详情参见对应 JSON 文件。

---

## 八、TTS API 端点说明

TTS 语音合成使用 HTTP GET 请求，由 `TTSHttpClient` 调用（`Services.swift`）。

### 端点

```
GET /tts
```

### 参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `t` | string | 是 | 待合成的文本内容 |
| `v` | string | 是 | 音色 ID（如 `zh-CN-YunyeNeural`） |
| `r` | int | 否 | 语速偏移（-100 ~ 100，0 为正常语速） |
| `p` | int | 否 | 音调偏移（-100 ~ 100，0 为正常音调） |
| `s` | string | 否 | 风格（如 `serious`, `cheerful`, `neutral`） |

### 返回

- Content-Type: `audio/mpeg`
- 二进制 MP3 音频流

### 调用示例

```bash
curl "http://192.168.0.68:37788/tts?t=测试&v=zh-CN-YunyeNeural&r=-10&p=-5&s=serious"
```
