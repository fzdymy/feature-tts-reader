# Feature TTS Reader

一个为 iPhone 设计的本地多角色小说朗读器，基于本地部署的 `fzdymy/tts` 服务。应用支持：

- 导入小说文本并自动扫描章节
- 提取人物名称、性别、年龄、语气等角色属性
- 为角色匹配音色、语速、音调和朗读风格
- 浏览并微调角色音色设置
- 读取当前章节或整本小说
- 支持本地 TTS 接口和开放式语音列表
- 支持本地音色目录：`chinese_voices_35.json` 与 `full_chinese_voices.json`

## 当前实现状态

已实现：
- TXT 文本导入与章节自动扫描
- 网格书架视图、书籍导入与清空管理
- 章节目录与阅读器视图
- 多角色识别与角色音色/参数配置界面
- 本地 TTS 调用，支持 Bearer Token 认证与 `api_key` 查询参数认证
- 本地音色目录与语音映射已完成：支持 `chinese_voices_35.json` 和 `full_chinese_voices.json`
- 阅读进度保存、书签添加/删除、深色/浅色主题、字号与行距调节
- 书架打开时自动定位到上次阅读章节（已实现恢复逻辑）

未覆盖 / 继续完善中：
- Core Data / Realm 本地数据库存储（当前使用 JSON 保存状态）
- 自定义字体导入与高级排版（当前使用 SwiftUI 文本展示）
- 全屏沉浸式翻页动画与 Core Text 精准排版
- 书架排序、搜索、分类、封面自动生成
- 后台播放、锁屏控制和音频会话管理

## 使用说明

1. 在 Xcode 中打开 `Package.swift`。
2. 选择设备为 iOS 17 或更高版本。
3. 运行前请先在应用设置中填写本地 `tts` 服务地址，例如 `http://127.0.0.1:8080`。
4. 请在“API Key”字段中填写你的 TTS 认证密钥。应用会自动使用 Bearer Token 头部认证，或将该值附加到 `?api_key=` 查询参数。
5. 在设置里选择语音目录：远程服务、本地 35 种音色或本地完整音色。
6. 导入小说文本，点击“扫描章节”与“识别角色”。
7. 选择章节，或切换为“全书模式”，然后点击播放。
5. 导入小说文本，点击“扫描章节”与“识别角色”。
6. 选择章节，或切换为“全书模式”，然后点击播放。

## GitHub Actions 打包

- 已配置 `.github/workflows/ios-build.yml` 进行自动构建。
- 该 workflow 使用 macOS Runner 和 Xcode 最新版本构建 iOS 可执行应用。
- 目前打包步骤已修正为直接复制 `build_output/Release-iphoneos/FeatureTTSReader.app` 并生成 IPA。
- 若要导出 IPA，请在仓库 Secret 中设置 `APPLE_TEAM_ID`（如果需要签名发布）。
- 源码会构建并生成 iOS App，然后归档并导出 `FeatureTTSReader_unsigned.ipa`。

## 本地查看构建日志

如果本机已安装 `gh` CLI，可使用以下命令查看 GitHub Actions 运行和日志：

```bash
gh run list
gh run view <run-id> --log
```

也可以触发新的工作流：

```bash
gh workflow run ios-build.yml
```

若需在 GitHub Action 中定位构建失败点，可打开对应运行并检查 `Build unsigned app product` 与 `Package app into IPA` 两个步骤。

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

认证方式：
- Bearer 头部认证：`Authorization: Bearer YOUR_TTS_API_KEY`
- Query 参数认证：`/api/v1/voices?api_key=YOUR_TTS_API_KEY`

## 说明

- 当前项目使用 SwiftUI 设计。若需要签名安装，可使用 `sideloadly` 或 `AltStore` 进行自签名安装。
- 应用会自动生成角色朗读脚本并按角色顺序合成音频。
- 若没有识别到角色，应用会生成默认“叙述者”。
