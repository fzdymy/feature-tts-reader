# Feature TTS Reader

一个为 iPhone 设计的本地多角色小说朗读器，基于本地部署的 `fzdymy/tts` 服务。应用支持：

- 导入小说文本并自动扫描章节
- 提取人物名称、性别、年龄、语气等角色属性
- 为角色匹配音色、语速、音调和朗读风格
- 浏览并微调角色音色设置
- 读取当前章节或整本小说
- 支持本地 TTS 接口和开放式语音列表

## 使用说明

1. 在 Xcode 中打开 `Package.swift`。
2. 选择设备为 iOS 17 或更高版本。
3. 运行前请先在应用设置中填写本地 `tts` 服务地址，例如 `http://127.0.0.1:8080`。
4. 可选填写 API Key。若服务未启用认证，可留空。
5. 导入小说文本，点击“扫描章节”与“识别角色”。
6. 选择章节，或切换为“全书模式”，然后点击播放。

## GitHub Actions 打包

- 已配置 `.github/workflows/ios-build.yml` 进行自动构建。
- 该 workflow 使用 macOS 15 Runner 和 Xcode 26.3.0。
- 若要导出 IPA，请在仓库 Secret 中设置 `APPLE_TEAM_ID`。
- 源码会构建并生成 Xcode 项目，然后归档并导出 IPA。

## TTS 接口兼容

本应用调用 `fzdymy/tts` 的 `api/v1/voices` 与 `api/v1/tts` 接口。示例：

- 语音列表接口：`GET /api/v1/voices`
- 文本转语音接口：`POST /api/v1/tts`

请求体格式：
```json
{
  "text": "你好，世界",
  "voice": "zh-CN-XiaoxiaoNeural",
  "rate": 20,
  "pitch": 10,
  "style": "cheerful",
  "api_key": "YOUR_TTS_API_KEY"
}
```

## 说明

- 当前项目使用 SwiftUI 设计。若需要签名安装，可使用 `sideloadly` 或 `AltStore` 进行自签名安装。
- 应用会自动生成角色朗读脚本并按角色顺序合成音频。
- 若没有识别到角色，应用会生成默认“叙述者”。
