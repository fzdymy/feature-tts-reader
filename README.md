# Feature TTS Reader

一个为 iPhone 设计的本地多角色小说朗读器，基于本地部署的 `fzdymy/tts` 服务。

## 功能

- 导入 TXT 小说文本，自动扫描章节
- 基于 `NLTokenizer` 中文分词的**角色自动识别**（姓名提取、频次统计、对话检测、关系图谱）
- 为角色匹配音色、语速、音调和朗读风格
- 多角色语音合成与朗读（当前章节或整本书）
- 阅读进度、书签、深色/浅色主题、字号/行距/段落间距调节
- 阅读器沉浸模式（进度条、百分比、时间、电量）
- 全文检索、角色音色设置、语音配置推荐
- CI 自动构建未签名 IPA，支持 sideload 安装

## 角色分析架构

```
character name   ──→  NLTokenizer 分词 + 频率过滤 + 30+ 上下文正则
extraction             NLTagger(.nameType) + 对话语境补充

dialogue         ──→  中文引号/书名号正则匹配 → 前文说话者推断
detection              支持「」""「」等多种引号格式

relationship     ──→  段落共现矩阵 + 对话边权重增强
graph                 输出 (source, target, weight)

attribute        ──→  基于上下文关键词的性别/年龄/语气推断
analysis              支持 30+ 性别关键词、15+ 年龄关键词
```

## 使用说明

1. 在 Xcode 中打开 `Package.swift`，目标 iOS 17+
2. 设置中填写 TTS 服务地址（如 `http://127.0.0.1:8080`）
3. 导入 TXT 小说 → 书架页 → 点击书籍 → 章节目录
4. 角色音色设置中点击「扫描全文」或「扫描当前章节」
5. 角色识别完成后，生成朗读脚本并播放

## 构建

```bash
# CI 自动构建未签名 IPA
# workflow: .github/workflows/ios-build.yml
# 产物: FeatureTTSReader_unsigned.ipa
```

## 技术栈

| 层 | 技术 |
|---|------|
| UI | SwiftUI, iOS 17+ |
| 状态管理 | ReaderStore (@MainActor ObservableObject) |
| 持久化 | JSON 状态文件 + UserDefaults + Core Data |
| 文本分析 | NaturalLanguage (NLTokenizer, NLTagger) |
| 语音合成 | AVSpeechSynthesizer + HTTP TTS API |
| 构建 | Swift Package Manager, GitHub Actions |
